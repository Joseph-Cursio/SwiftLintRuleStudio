import Foundation
import SQLite3

extension ViolationStorage {
    func storeViolations(_ violations: [Violation], for workspaceId: UUID) async throws {
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
        logDeletedViolations(deleted)

        let statement = try prepareInsertStatement(db: db)
        defer { sqlite3_finalize(statement) }

        let insertionResult = try insertViolations(
            violations,
            workspaceId: workspaceId,
            db: db,
            statement: statement
        )
        logDuplicateViolations(insertionResult, total: violations.count)
        
        // Commit transaction
        try executeSQL("COMMIT", db: db)
        transactionCommitted = true
        
        print("💾 Stored \(insertionResult.insertedCount) violations for workspace: \(workspaceId.uuidString)")
    }
    
    private func beginTransaction(db: OpaquePointer) throws {
        try executeSQL("BEGIN TRANSACTION", db: db)
    }

    private struct InsertionResult {
        let insertedCount: Int
        let duplicateIDs: Set<String>
        let uniqueCount: Int
    }

    private func insertViolations(
        _ violations: [Violation],
        workspaceId: UUID,
        db: OpaquePointer,
        statement: OpaquePointer
    ) throws -> InsertionResult {
        var insertedCount = 0
        var seenIDs = Set<String>()
        var duplicateIDs = Set<String>()

        for (index, violation) in violations.enumerated() {
            resetStatement(statement, shouldReset: index > 0)
            trackDuplicateIDs(
                violation: violation,
                index: index,
                seenIDs: &seenIDs,
                duplicateIDs: &duplicateIDs
            )

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
        }

        return InsertionResult(
            insertedCount: insertedCount,
            duplicateIDs: duplicateIDs,
            uniqueCount: seenIDs.count
        )
    }

    private func trackDuplicateIDs(
        violation: Violation,
        index: Int,
        seenIDs: inout Set<String>,
        duplicateIDs: inout Set<String>
    ) {
        let idString = violation.id.uuidString
        if seenIDs.contains(idString) {
            duplicateIDs.insert(idString)
            if duplicateIDs.count <= 3 {
                print("⚠️  Duplicate violation ID found: \(idString) at index \(index)")
            }
        } else {
            seenIDs.insert(idString)
        }
    }

    private func logDeletedViolations(_ deleted: Int) {
        if deleted > 0 {
            print("🗑️  Deleted \(deleted) existing violations for workspace before inserting new ones")
        }
    }

    private func logDuplicateViolations(_ result: InsertionResult, total: Int) {
        guard !result.duplicateIDs.isEmpty else { return }
        let message = "⚠️  Found \(result.duplicateIDs.count) unique duplicate IDs in violation set " +
            "(total violations: \(total), unique IDs: \(result.uniqueCount))"
        print(message)
    }
    
    private func deleteExistingViolations(for workspaceId: UUID, db: OpaquePointer) throws -> Int {
        let deleteSQL = "DELETE FROM violations WHERE workspace_id = ?;"
        var deleteStatement: OpaquePointer?
        defer { sqlite3_finalize(deleteStatement) }

        guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStatement, nil) == SQLITE_OK,
              let statement = deleteStatement else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
        let deleteError = "Failed to allocate memory for delete workspace ID"
        try bindText(
            workspaceId.uuidString,
            index: 1,
            statement: statement,
            errorMessage: deleteError
        )
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw ViolationStorageError.sqlError(errorMsg)
        }
        return Int(sqlite3_changes(db))
    }
    
    private func prepareInsertStatement(db: OpaquePointer) throws -> OpaquePointer {
        let insertSQL = """
        INSERT OR REPLACE INTO violations
        (id, workspace_id, rule_id, file_path, line, column, severity, message,
         detected_at, resolved_at, suppressed, suppression_reason)
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
        let idError = "Failed to allocate memory for violation ID"
        let workspaceError = "Failed to allocate memory for workspace ID"
        let ruleError = "Failed to allocate memory for rule ID"
        let filePathError = "Failed to allocate memory for file path"
        try bindText(idString, index: 1, statement: statement, errorMessage: idError)
        try bindText(workspaceId.uuidString, index: 2, statement: statement, errorMessage: workspaceError)
        try bindText(violation.ruleID, index: 3, statement: statement, errorMessage: ruleError)
        try bindText(violation.filePath, index: 4, statement: statement, errorMessage: filePathError)
        sqlite3_bind_int(statement, 5, Int32(violation.line))
        if let column = violation.column {
            sqlite3_bind_int(statement, 6, Int32(column))
        } else {
            sqlite3_bind_null(statement, 6)
        }
        let severityError = "Failed to allocate memory for severity"
        let messageError = "Failed to allocate memory for message"
        try bindText(violation.severity.rawValue, index: 7, statement: statement, errorMessage: severityError)
        try bindText(violation.message, index: 8, statement: statement, errorMessage: messageError)
        sqlite3_bind_double(statement, 9, violation.detectedAt.timeIntervalSince1970)
        if let resolvedAt = violation.resolvedAt {
            sqlite3_bind_double(statement, 10, resolvedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 10)
        }
        sqlite3_bind_int(statement, 11, violation.suppressed ? 1 : 0)
        if let reason = violation.suppressionReason {
            let suppressionError = "Failed to allocate memory for suppression reason"
            try bindText(reason, index: 12, statement: statement, errorMessage: suppressionError)
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
    
    func suppressViolations(_ violationIds: [UUID], reason: String) async throws {
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
    
    func resolveViolations(_ violationIds: [UUID]) async throws {
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
    
    func deleteViolations(for workspaceId: UUID) async throws {
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
}
