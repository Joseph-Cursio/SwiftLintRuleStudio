import Foundation
import SQLite3

extension ViolationStorage {
    func closeDatabase() {
        if let db = database {
            sqlite3_close(db)
            database = nil
        }
    }
    
    func executeSQL(_ sql: String, db: OpaquePointer? = nil) throws {
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
}
