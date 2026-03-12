import Foundation
import SQLite3

extension ViolationStorage {
    func closeDatabase() {
        if let handle = database {
            sqlite3_close(handle)
            database = nil
        }
    }

    func executeSQL(_ sql: String, dbHandle: OpaquePointer? = nil) throws {
        let resolved = dbHandle ?? database
        guard let handle = resolved else {
            throw ViolationStorageError.databaseNotOpen
        }

        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }

        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(handle))
            throw ViolationStorageError.sqlError(errorMsg)
        }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let errorMsg = String(cString: sqlite3_errmsg(handle))
            throw ViolationStorageError.sqlError(errorMsg)
        }
    }
}
