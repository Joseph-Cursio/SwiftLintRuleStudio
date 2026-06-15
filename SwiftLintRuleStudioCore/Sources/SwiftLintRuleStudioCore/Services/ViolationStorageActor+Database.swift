import Foundation

public extension ViolationStorageActor {
    /// Closes the SQLite database connection
    func closeDatabase() {
        database?.close()
        database = nil
    }

    /// Executes a raw SQL statement against the database, expecting it to complete
    /// without producing rows.
    func executeSQL(_ sql: String) throws {
        guard let database else {
            throw ViolationStorageError.databaseNotOpen
        }
        try database.execute(sql)
    }
}
