//
//  SQLiteStatement.swift
//  SwiftLintRuleStudio
//
//  Typed wrapper around a prepared SQLite statement. Together with `SQLiteDatabase`,
//  this is the only place that touches `OpaquePointer` and the `sqlite3_*` C API.
//

import Foundation
import SQLite3

/// The outcome of advancing a statement with `step()`.
nonisolated enum SQLiteStepResult {
    /// A row is available to read (`SQLITE_ROW`).
    case row
    /// Execution finished successfully (`SQLITE_DONE`).
    case done
    /// Any other result code — an error; read `SQLiteDatabase.lastErrorMessage`.
    case error
}

/// A typed wrapper around a prepared SQLite statement (`sqlite3_stmt *`).
///
/// A statement is created, used, and finalized within a single actor-isolated operation,
/// so it never escapes the actor and needs no `Sendable` conformance. It finalizes itself
/// on `deinit`, replacing the manual `defer { sqlite3_finalize(...) }` the callers used.
///
/// `nonisolated` because the Core layer runs under `defaultIsolation(MainActor.self)`,
/// but statements are driven by `ViolationStorageActor` (a standalone actor).
nonisolated final class SQLiteStatement {
    /// `SQLITE_TRANSIENT` tells SQLite to copy bound bytes immediately, during the bind
    /// call, so the caller's buffer need not outlive it. The C macro is
    /// `(sqlite3_destructor_type)(-1)`; this `unsafeBitCast` is its canonical Swift
    /// spelling, confined to the SQLite wrappers so no other file needs the escape hatch.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let handle: OpaquePointer

    /// Wraps an already-prepared statement handle. Created only by `SQLiteDatabase.prepare`.
    init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_finalize(handle)
    }

    // MARK: - Binding (1-based parameter index)

    /// Binds `text`. SQLite copies the bytes immediately (`SQLITE_TRANSIENT`), so no
    /// manual buffer management is required.
    func bind(_ text: String, at index: Int32) {
        sqlite3_bind_text(handle, index, text, -1, Self.transient)
    }

    func bind(_ value: Int32, at index: Int32) {
        sqlite3_bind_int(handle, index, value)
    }

    func bind(_ value: Double, at index: Int32) {
        sqlite3_bind_double(handle, index, value)
    }

    func bindNull(at index: Int32) {
        sqlite3_bind_null(handle, index)
    }

    /// Resets the statement so it can be re-executed, and (by default) clears its bindings.
    func reset(clearingBindings: Bool = true) {
        sqlite3_reset(handle)
        if clearingBindings {
            sqlite3_clear_bindings(handle)
        }
    }

    /// Advances execution by one step.
    func step() -> SQLiteStepResult {
        switch sqlite3_step(handle) {
        case SQLITE_ROW: return .row
        case SQLITE_DONE: return .done
        default: return .error
        }
    }

    // MARK: - Reading columns (0-based column index)

    func columnInt(at index: Int32) -> Int {
        Int(sqlite3_column_int(handle, index))
    }

    func columnDouble(at index: Int32) -> Double {
        sqlite3_column_double(handle, index)
    }

    /// The column's text value, or `nil` when the column is NULL.
    func columnText(at index: Int32) -> String? {
        guard let cString = sqlite3_column_text(handle, index) else { return nil }
        return String(cString: cString)
    }

    /// Whether the column holds SQL NULL.
    func columnIsNull(at index: Int32) -> Bool {
        sqlite3_column_type(handle, index) == SQLITE_NULL
    }
}
