//
//  ViolationStorage.swift
//  SwiftLintRuleStudio
//
//  Service for storing and querying violations in SQLite database
//

import Foundation
import SQLite3

// sqliteTransient is a function pointer constant that tells SQLite to copy the string
// In Swift, we need to define it ourselves
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Protocol for violation storage operations
/// All methods are async, so callers properly await across isolation boundaries
/// whether the conforming type is @MainActor or a standalone actor.
protocol ViolationStorageProtocol: Sendable {
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

    let databasePath: URL
    let useInMemory: Bool
    // nonisolated(unsafe) is required because OpaquePointer is not Sendable.
    // Mutated only by actor-isolated closeDatabase() and non-isolated deinit
    // (which runs after all actor tasks complete).
    nonisolated(unsafe) var database: OpaquePointer?

    // MARK: - Initialization

    init(databasePath: URL? = nil, useInMemory: Bool = false) throws {
        self.useInMemory = useInMemory

        self.databasePath = try Self.resolveDatabasePath(databasePath: databasePath, useInMemory: useInMemory)
        let databaseHandle = try Self.openDatabase(at: self.databasePath, useInMemory: useInMemory)
        try Self.createSchema(in: databaseHandle)
        self.database = databaseHandle
    }

    deinit {
        // Use sqlite3_close_v2 which safely defers closing until all outstanding
        // statements are finalized — avoids "illegal multi-threaded access" when
        // deinit runs on a thread pool thread while statements are still pending.
        if let handle = database {
            sqlite3_close_v2(handle)
        }
    }

    // MARK: - ViolationStorageProtocol

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
