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
    
    let databasePath: URL
    let useInMemory: Bool
    // Marked nonisolated(unsafe) to allow initialization from MainActor context
    // Still safe because all access is through actor-isolated methods
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
        // Deinit cannot be async, but closing the database is a synchronous operation
        // Accessing database directly in deinit is safe since deinit runs when actor is being deallocated
        if let db = database {
            sqlite3_close(db)
            database = nil
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
