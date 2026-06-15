import Foundation

extension ViolationStorageActor {
    /// Resolve the database file path, using in-memory or default location as needed
    public static func resolveDatabasePath(databasePath: URL?, useInMemory: Bool) throws -> URL {
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

    /// Create the violations database schema if it does not already exist
    static func createSchema(in database: SQLiteDatabase) throws {
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

        try database.execute(createViolationsTable)
        try database.execute(createIndexes)
    }
}
