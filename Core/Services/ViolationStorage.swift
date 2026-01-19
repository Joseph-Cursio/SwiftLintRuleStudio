//
//  ViolationStorage.swift
//  SwiftLintRuleStudio
//
//  Service for storing and querying violations in SQLite database
//

import Foundation
import SQLite3

// SQLITE_TRANSIENT is a function pointer constant that tells SQLite to copy the string
// In Swift, we need to define it ourselves
// swiftlint:disable:next identifier_name
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Protocol for violation storage operations
protocol ViolationStorageProtocol {
    func storeViolations(_ violations: [Violation], for workspaceId: UUID) async throws
    func fetchViolations(filter: ViolationFilter, workspaceId: UUID?) async throws -> [Violation]
    func suppressViolations(_ violationIds: [UUID], reason: String) async throws
    func resolveViolations(_ violationIds: [UUID]) async throws
    func deleteViolations(for workspaceId: UUID) async throws
    func getViolationCount(filter: ViolationFilter, workspaceId: UUID?) async throws -> Int
}

/// SQLite-based violation storage
/// Uses Swift concurrency actor for thread-safe database access
actor ViolationStorage: ViolationStorageProtocol {
    
    // MARK: - Properties
    
    private let databasePath: URL
    private let useInMemory: Bool
    // Marked nonisolated(unsafe) to allow initialization from MainActor context
    // Still safe because all access is through actor-isolated methods
    nonisolated(unsafe) private var database: OpaquePointer?
    
    // MARK: - Initialization
    
    init(databasePath: URL? = nil, useInMemory: Bool = false) throws {
        self.useInMemory = useInMemory

        self.databasePath = try Self.resolveDatabasePath(databasePath: databasePath, useInMemory: useInMemory)
        let databaseHandle = try Self.openDatabase(at: self.databasePath, useInMemory: useInMemory)
        try Self.createSchema(in: databaseHandle)
        self.database = databaseHandle
    }

    private static func resolveDatabasePath(databasePath: URL?, useInMemory: Bool) throws -> URL {
        if useInMemory {
            return URL(fileURLWithPath: ":memory:")
        }
        if let customPath = databasePath {
            return customPath
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dbDir = appSupport.appendingPathComponent("SwiftLintRuleStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        return dbDir.appendingPathComponent("violations.db")
    }

    private static func openDatabase(at path: URL, useInMemory: Bool) throws -> OpaquePointer {
        let dbPath: String = useInMemory ? ":memory:" : path.path
        if !useInMemory {
            let parentDir = path.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                throw ViolationStorageError.databaseOpenFailed("Database directory does not exist: \(parentDir.path)")
            }
        }

        var db: OpaquePointer?
        let result = sqlite3_open(dbPath, &db)
        guard result == SQLITE_OK else {
            let errorMsg = db != nil ? String(cString: sqlite3_errmsg(db)) : "Unknown error (code: \(result))"
            if db != nil {
                sqlite3_close(db)
            }
            throw ViolationStorageError.databaseOpenFailed("Failed to open database at '\(dbPath)': \(errorMsg)")
        }
        guard let databaseHandle = db else {
            throw ViolationStorageError.databaseNotOpen
        }
        return databaseHandle
    }

    private static func createSchema(in databaseHandle: OpaquePointer) throws {
        let createViolationsTable = """
        CREATE TABLE IF NOT EXISTS violations (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            rule_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            line INTEGER NOT NULL,
            column INTEGER,
            severity TEXT NOT NULL,
            message TEXT NOT NULL,
            detected_at REAL NOT NULL,
            resolved_at REAL,
            suppressed INTEGER NOT NULL DEFAULT 0,
            suppression_reason TEXT
        );
        """

        let createIndexes = """
        CREATE INDEX IF NOT EXISTS idx_violations_workspace ON violations(workspace_id);
        CREATE INDEX IF NOT EXISTS idx_violations_rule ON violations(rule_id);
        CREATE INDEX IF NOT EXISTS idx_violations_file ON violations(file_path);
        CREATE INDEX IF NOT EXISTS idx_violations_detected ON violations(detected_at);
        CREATE INDEX IF NOT EXISTS idx_violations_workspace_rule ON violations(workspace_id, rule_id);
        """

        try executeInitSQL(createViolationsTable, on: databaseHandle)
        try executeInitSQL(createIndexes, on: databaseHandle)
    }

    private static func executeInitSQL(_ sql: String, on databaseHandle: OpaquePointer) throws {
        var statement: OpaquePointer?
        defer {
            if let stmt = statement {
                sqlite3_finalize(stmt)
            }
        }
        guard sqlite3_prepare_v2(databaseHandle, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(databaseHandle))
            throw ViolationStorageError.sqlError(errorMsg)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errorMsg = String(cString: sqlite3_errmsg(databaseHandle))
            throw ViolationStorageError.sqlError(errorMsg)
        }
    }
    
    deinit {
        // Deinit cannot be async, but closing the database is a synchronous operation
        // Accessing database directly in deinit is safe since deinit runs when actor is being deallocated
        if let db = database {
            sqlite3_close(db)
            database = nil
        }
    }
    
    // MARK: - Database Management
    
    private func closeDatabase() {
        if let db = database {
            sqlite3_close(db)
            database = nil
        }
    }
    
    private func executeSQL(_ sql: String, db: OpaquePointer? = nil) throws {
        let databaseHandle = db ?? database
        guard let db = databaseHandle else {
            throw ViolationStorageError.databaseNotOpen
        }
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw ViolationStorageError.sqlError(errorMsg)
        }
        
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw ViolationStorageError.sqlError(errorMsg)
        }
    }
    
    // MARK: - ViolationStorageProtocol
    
    // Actor methods must be async per protocol, but don't need await internally (already isolated)
    func storeViolations(_ violations: [Violation], for workspaceId: UUID) async throws { // swiftlint:disable:this async_without_await
        guard let db = database else {
            throw ViolationStorageError.databaseNotOpen
        }
        
        // Use transaction for performance
        try beginTransaction(db: db)
        
        var transactionCommitted = false
        defer {
            if !transactionCommitted {
                // Only rollback if we didn't commit successfully
                try? executeSQL("ROLLBACK", db: db)
            }
        }
        
        let deleted = try deleteExistingViolations(for: workspaceId, db: db)
        if deleted > 0 {
            print("🗑️  Deleted \(deleted) existing violations for workspace before inserting new ones")
        }

        let statement = try prepareInsertStatement(db: db)
        defer { sqlite3_finalize(statement) }
        
        var insertedCount = 0
        var seenIDs = Set<String>()
        var duplicateIDs = Set<String>()
        
        for (index, violation) in violations.enumerated() {
            resetStatement(statement, shouldReset: index > 0)
            
            // Check for duplicate IDs
            let idString = violation.id.uuidString
            if seenIDs.contains(idString) {
                duplicateIDs.insert(idString)
                if duplicateIDs.count <= 3 {
                    print("⚠️  Duplicate violation ID found: \(idString) at index \(index)")
                }
            } else {
                seenIDs.insert(idString)
            }
            
            try bindViolation(
                violation,
                workspaceId: workspaceId,
                statement: statement
            )
            
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                insertedCount += 1
            } else {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                print("❌ Error inserting violation \(index): \(errorMsg) (code: \(stepResult))")
                sqlite3_reset(statement)
                throw ViolationStorageError.sqlError("Failed to insert violation at index \(index): \(errorMsg)")
            }
            
            // Note: We don't reset here - we'll reset at the start of the next iteration
            // This is more efficient and ensures proper state management
        }
        
        if !duplicateIDs.isEmpty {
            print("⚠️  Found \(duplicateIDs.count) unique duplicate IDs in violation set (total violations: \(violations.count), unique IDs: \(seenIDs.count))")
        }
        
        // Commit transaction
        try executeSQL("COMMIT", db: db)
        transactionCommitted = true
        
        print("💾 Stored \(insertedCount) violations for workspace: \(workspaceId.uuidString)")
    }

    private func beginTransaction(db: OpaquePointer) throws {
        try executeSQL("BEGIN TRANSACTION", db: db)
    }

    private func deleteExistingViolations(for workspaceId: UUID, db: OpaquePointer) throws -> Int {
        let deleteSQL = "DELETE FROM violations WHERE workspace_id = ?;"
        var deleteStatement: OpaquePointer?
        defer { sqlite3_finalize(deleteStatement) }

        guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStatement, nil) == SQLITE_OK,
              let statement = deleteStatement else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
        try bindText(workspaceId.uuidString, index: 1, statement: statement, errorMessage: "Failed to allocate memory for delete workspace ID")
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw ViolationStorageError.sqlError(errorMsg)
        }
        return Int(sqlite3_changes(db))
    }

    private func prepareInsertStatement(db: OpaquePointer) throws -> OpaquePointer {
        let insertSQL = """
        INSERT OR REPLACE INTO violations
        (id, workspace_id, rule_id, file_path, line, column, severity, message, detected_at, resolved_at, suppressed, suppression_reason)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
        guard let prepared = statement else {
            throw ViolationStorageError.databaseNotOpen
        }
        return prepared
    }

    private func resetStatement(_ statement: OpaquePointer, shouldReset: Bool) {
        if shouldReset {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
    }

    private func bindViolation(_ violation: Violation, workspaceId: UUID, statement: OpaquePointer) throws {
        let idString = violation.id.uuidString
        try bindText(idString, index: 1, statement: statement, errorMessage: "Failed to allocate memory for violation ID")
        try bindText(workspaceId.uuidString, index: 2, statement: statement, errorMessage: "Failed to allocate memory for workspace ID")
        try bindText(violation.ruleID, index: 3, statement: statement, errorMessage: "Failed to allocate memory for rule ID")
        try bindText(violation.filePath, index: 4, statement: statement, errorMessage: "Failed to allocate memory for file path")
        sqlite3_bind_int(statement, 5, Int32(violation.line))
        if let column = violation.column {
            sqlite3_bind_int(statement, 6, Int32(column))
        } else {
            sqlite3_bind_null(statement, 6)
        }
        try bindText(violation.severity.rawValue, index: 7, statement: statement, errorMessage: "Failed to allocate memory for severity")
        try bindText(violation.message, index: 8, statement: statement, errorMessage: "Failed to allocate memory for message")
        sqlite3_bind_double(statement, 9, violation.detectedAt.timeIntervalSince1970)
        if let resolvedAt = violation.resolvedAt {
            sqlite3_bind_double(statement, 10, resolvedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 10)
        }
        sqlite3_bind_int(statement, 11, violation.suppressed ? 1 : 0)
        if let reason = violation.suppressionReason {
            try bindText(reason, index: 12, statement: statement, errorMessage: "Failed to allocate memory for suppression reason")
        } else {
            sqlite3_bind_null(statement, 12)
        }
    }

    private func bindText(_ value: String, index: Int32, statement: OpaquePointer, errorMessage: String) throws {
        guard let cString = strdup(value) else {
            throw ViolationStorageError.sqlError(errorMessage)
        }
        sqlite3_bind_text(statement, index, cString, -1, free)
    }
    
    // swiftlint:disable:next async_without_await
    // Actor methods must be async per protocol, but don't need await internally (already isolated)
    func fetchViolations(filter: ViolationFilter, workspaceId: UUID?) async throws -> [Violation] { // swiftlint:disable:this async_without_await
        guard let db = database else {
            throw ViolationStorageError.databaseNotOpen
        }
        let query = buildFilterQuery(filter: filter, workspaceId: workspaceId)
        let sql = "SELECT id, workspace_id, rule_id, file_path, line, column, severity, message, detected_at, resolved_at, suppressed, suppression_reason FROM violations \(query.whereClause) ORDER BY detected_at DESC;"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
        
        try bindParameters(query.parameters, to: statement, errorMessagePrefix: "Failed to allocate memory for parameter")
        
        var violations: [Violation] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let violation = parseViolation(from: statement) {
                violations.append(violation)
            }
        }
        
        return violations
    }
    
    // swiftlint:disable:next async_without_await
    // Actor methods must be async per protocol, but don't need await internally (already isolated)
    func suppressViolations(_ violationIds: [UUID], reason: String) async throws { // swiftlint:disable:this async_without_await
        guard let db = database else {
            throw ViolationStorageError.databaseNotOpen
        }
        
        let placeholders = violationIds.map { _ in "?" }.joined(separator: ", ")
        let sql = "UPDATE violations SET suppressed = 1, suppression_reason = ? WHERE id IN (\(placeholders));"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
        
        // Bind reason using strdup to ensure string persists
        guard let reasonCString = strdup(reason) else {
            throw ViolationStorageError.sqlError("Failed to allocate memory for suppression reason")
        }
        sqlite3_bind_text(statement, 1, reasonCString, -1, free)
        
        // Bind violation IDs using strdup
        var idCStrings: [UnsafeMutablePointer<CChar>?] = []
        defer {
            // Clean up any allocated strings if we fail before binding
            for cString in idCStrings {
                if let cString = cString {
                    free(cString)
                }
            }
        }
        
        for (index, id) in violationIds.enumerated() {
            guard let idCString = strdup(id.uuidString) else {
                throw ViolationStorageError.sqlError("Failed to allocate memory for violation ID")
            }
            idCStrings.append(idCString)
            sqlite3_bind_text(statement, Int32(index + 2), idCString, -1, free)
        }
        
        // Clear the defer cleanup since SQLite will manage the memory now
        idCStrings.removeAll()
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
    }
    
    // swiftlint:disable:next async_without_await
    // Actor methods must be async per protocol, but don't need await internally (already isolated)
    func resolveViolations(_ violationIds: [UUID]) async throws { // swiftlint:disable:this async_without_await
        guard let db = database else {
            throw ViolationStorageError.databaseNotOpen
        }
        
        let placeholders = violationIds.map { _ in "?" }.joined(separator: ", ")
        let sql = "UPDATE violations SET resolved_at = ? WHERE id IN (\(placeholders));"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
        
        sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
        
        // Bind violation IDs using strdup
        var idCStrings: [UnsafeMutablePointer<CChar>?] = []
        defer {
            // Clean up any allocated strings if we fail before binding
            for cString in idCStrings {
                if let cString = cString {
                    free(cString)
                }
            }
        }
        
        for (index, id) in violationIds.enumerated() {
            guard let idCString = strdup(id.uuidString) else {
                throw ViolationStorageError.sqlError("Failed to allocate memory for violation ID")
            }
            idCStrings.append(idCString)
            sqlite3_bind_text(statement, Int32(index + 2), idCString, -1, free)
        }
        
        // Clear the defer cleanup since SQLite will manage the memory now
        idCStrings.removeAll()
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
    }
    
    // swiftlint:disable:next async_without_await
    // Actor methods must be async per protocol, but don't need await internally (already isolated)
    func deleteViolations(for workspaceId: UUID) async throws { // swiftlint:disable:this async_without_await
        guard let db = database else {
            throw ViolationStorageError.databaseNotOpen
        }
        
        let sql = "DELETE FROM violations WHERE workspace_id = ?;"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
        
        guard let deleteWorkspaceIdCString = strdup(workspaceId.uuidString) else {
            throw ViolationStorageError.sqlError("Failed to allocate memory for delete workspace ID")
        }
        sqlite3_bind_text(statement, 1, deleteWorkspaceIdCString, -1, free)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
    }
    
    // swiftlint:disable:next async_without_await
    // Actor methods must be async per protocol, but don't need await internally (already isolated)
    func getViolationCount(filter: ViolationFilter, workspaceId: UUID?) async throws -> Int { // swiftlint:disable:this async_without_await
        guard let db = database else {
            throw ViolationStorageError.databaseNotOpen
        }
        let query = buildFilterQuery(filter: filter, workspaceId: workspaceId)
        let sql = "SELECT COUNT(*) FROM violations \(query.whereClause);"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
        
        try bindParameters(query.parameters, to: statement, errorMessagePrefix: "Failed to allocate memory for count parameter")
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
        
        return Int(sqlite3_column_int(statement, 0))
    }

    private struct FilterQuery {
        let whereClause: String
        let parameters: [Any]
    }

    private func buildFilterQuery(filter: ViolationFilter, workspaceId: UUID?) -> FilterQuery {
        var conditions: [String] = []
        var parameters: [Any] = []

        if let workspaceId = workspaceId {
            conditions.append("workspace_id = ?")
            parameters.append(workspaceId.uuidString)
        }

        if let ruleIDs = filter.ruleIDs, !ruleIDs.isEmpty {
            let placeholders = ruleIDs.map { _ in "?" }.joined(separator: ", ")
            conditions.append("rule_id IN (\(placeholders))")
            parameters.append(contentsOf: ruleIDs)
        }

        if let filePaths = filter.filePaths, !filePaths.isEmpty {
            let placeholders = filePaths.map { _ in "?" }.joined(separator: ", ")
            conditions.append("file_path IN (\(placeholders))")
            parameters.append(contentsOf: filePaths)
        }

        if let severities = filter.severities, !severities.isEmpty {
            let placeholders = severities.map { _ in "?" }.joined(separator: ", ")
            conditions.append("severity IN (\(placeholders))")
            parameters.append(contentsOf: severities.map { $0.rawValue })
        }

        if let suppressedOnly = filter.suppressedOnly {
            conditions.append("suppressed = ?")
            parameters.append(suppressedOnly ? 1 : 0)
        }

        if let dateRange = filter.dateRange {
            conditions.append("detected_at >= ? AND detected_at <= ?")
            parameters.append(dateRange.lowerBound.timeIntervalSince1970)
            parameters.append(dateRange.upperBound.timeIntervalSince1970)
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        return FilterQuery(whereClause: whereClause, parameters: parameters)
    }

    private func bindParameters(
        _ parameters: [Any],
        to statement: OpaquePointer?,
        errorMessagePrefix: String
    ) throws {
        for (index, param) in parameters.enumerated() {
            let bindIndex = Int32(index + 1)
            if let string = param as? String {
                guard let stringCString = strdup(string) else {
                    throw ViolationStorageError.sqlError("\(errorMessagePrefix) \(bindIndex)")
                }
                sqlite3_bind_text(statement, bindIndex, stringCString, -1, free)
            } else if let int = param as? Int {
                sqlite3_bind_int(statement, bindIndex, Int32(int))
            } else if let double = param as? Double {
                sqlite3_bind_double(statement, bindIndex, double)
            }
        }
    }

    private func parseViolation(from statement: OpaquePointer?) -> Violation? {
        guard let idString = sqlite3_column_text(statement, 0),
              let id = UUID(uuidString: String(cString: idString)),
              let ruleID = sqlite3_column_text(statement, 2),
              let filePath = sqlite3_column_text(statement, 3),
              let severityString = sqlite3_column_text(statement, 6),
              let message = sqlite3_column_text(statement, 7) else {
            return nil
        }

        let line = Int(sqlite3_column_int(statement, 4))
        let column = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 5))
        let detectedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))
        let resolvedAt = sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 9))
        let suppressed = sqlite3_column_int(statement, 10) != 0
        let suppressionReason = sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 11))
        let severity = Severity(rawValue: String(cString: severityString)) ?? .warning

        return Violation(
            id: id,
            ruleID: String(cString: ruleID),
            filePath: String(cString: filePath),
            line: line,
            column: column,
            severity: severity,
            message: String(cString: message),
            detectedAt: detectedAt,
            resolvedAt: resolvedAt,
            suppressed: suppressed,
            suppressionReason: suppressionReason
        )
    }
}

// MARK: - Errors

enum ViolationStorageError: LocalizedError {
    case databaseNotOpen
    case databaseOpenFailed(String)
    case sqlError(String)
    
    var errorDescription: String? {
        switch self {
        case .databaseNotOpen:
            return "Database is not open"
        case .databaseOpenFailed(let message):
            return "Failed to open database: \(message)"
        case .sqlError(let message):
            return "SQL error: \(message)"
        }
    }
}
