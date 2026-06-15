//
//  SQLiteDatabase.swift
//  SwiftLintRuleStudio
//
//  Typed wrapper around a SQLite connection. Together with `SQLiteStatement`, this is the
//  *only* place in the codebase that touches `OpaquePointer` and the `sqlite3_*` functions
//  — every other layer works through these wrappers, so the raw, memory-unsafe surface is
//  confined to two auditable files.
//

import Foundation
import SQLite3

/// A typed wrapper around a SQLite connection (`sqlite3 *`).
///
/// `nonisolated` because the Core layer runs under `defaultIsolation(MainActor.self)`,
/// but the connection is driven by `ViolationStorageActor` (a standalone actor, not the
/// main actor), so it must opt out of main-actor isolation to be usable from it.
///
/// `@unchecked Sendable`: the connection is owned by `ViolationStorageActor`, which
/// serializes every access through actor isolation, so it is never used concurrently.
/// SQLite connections are not thread-safe for concurrent use; that invariant is upheld
/// by the owning actor, not the type itself — hence `unchecked`.
nonisolated final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    /// Opens (or creates) the database at `path`, or an in-memory database when
    /// `useInMemory` is true.
    static func open(at path: URL, useInMemory: Bool) throws -> SQLiteDatabase {
        let dbPath: String = useInMemory ? ":memory:" : path.path
        if !useInMemory {
            let parentDir = path.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                throw ViolationStorageError.databaseOpenFailed(
                    "Database directory does not exist: \(parentDir.path)"
                )
            }
        }

        var dbHandle: OpaquePointer?
        let result = sqlite3_open(dbPath, &dbHandle)
        guard result == SQLITE_OK else {
            let errorMsg = dbHandle != nil
                ? String(cString: sqlite3_errmsg(dbHandle))
                : "Unknown error (code: \(result))"
            if dbHandle != nil {
                sqlite3_close(dbHandle)
            }
            throw ViolationStorageError.databaseOpenFailed(
                "Failed to open database at '\(dbPath)': \(errorMsg)"
            )
        }
        guard let dbHandle else {
            throw ViolationStorageError.databaseNotOpen
        }
        return SQLiteDatabase(handle: dbHandle)
    }

    /// The most recent error message from the connection (or a closed-state message).
    var lastErrorMessage: String {
        guard let handle else { return "Database is not open" }
        return String(cString: sqlite3_errmsg(handle))
    }

    /// The number of rows changed by the most recently completed statement.
    var changes: Int {
        handle.map { Int(sqlite3_changes($0)) } ?? 0
    }

    /// Compiles `sql` into a prepared statement.
    func prepare(_ sql: String) throws -> SQLiteStatement {
        guard let handle else { throw ViolationStorageError.databaseNotOpen }
        var statementHandle: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statementHandle, nil) == SQLITE_OK,
              let statementHandle else {
            throw ViolationStorageError.sqlError(String(cString: sqlite3_errmsg(handle)))
        }
        return SQLiteStatement(handle: statementHandle)
    }

    /// Prepares and runs `sql`, expecting it to complete without producing rows.
    func execute(_ sql: String) throws {
        let statement = try prepare(sql)
        guard statement.step() == .done else {
            throw ViolationStorageError.sqlError(lastErrorMessage)
        }
    }

    /// Explicitly closes the connection (`sqlite3_close`). The wrapper is inert afterward;
    /// `deinit` will not double-close.
    func close() {
        if let handle {
            sqlite3_close(handle)
            self.handle = nil
        }
    }

    deinit {
        // sqlite3_close_v2 defers the actual close until any outstanding statements are
        // finalized — avoiding "illegal multi-threaded access" when deinit runs on a
        // thread-pool thread while statements are still pending. A prior explicit close()
        // has already nilled the handle, so this is a no-op in that case.
        if let handle {
            sqlite3_close_v2(handle)
        }
    }
}
