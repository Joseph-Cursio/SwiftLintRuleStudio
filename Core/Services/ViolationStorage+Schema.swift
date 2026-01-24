import Foundation
import SQLite3

extension ViolationStorage {
    static func resolveDatabasePath(databasePath: URL?, useInMemory: Bool) throws -> URL {
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
    
    static func openDatabase(at path: URL, useInMemory: Bool) throws -> OpaquePointer {
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
    
    static func createSchema(in databaseHandle: OpaquePointer) throws {
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
}
