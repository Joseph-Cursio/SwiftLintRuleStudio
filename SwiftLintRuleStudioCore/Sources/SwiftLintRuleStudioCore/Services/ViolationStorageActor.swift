//
//  ViolationStorage.swift
//  SwiftLintRuleStudio
//
//  Service for storing and querying violations in SQLite database
//

import Foundation

/// Protocol for violation storage operations
/// All methods are async, so callers properly await across isolation boundaries
/// whether the conforming type is @MainActor or a standalone actor.
public protocol ViolationStorageProtocol: Sendable {
    func storeViolations(_ violations: [Violation], for workspaceId: UUID) async throws
    func fetchViolations(filter: ViolationFilter, workspaceId: UUID?) async throws -> [Violation]
    func suppressViolations(_ violationIds: [UUID], reason: String) async throws
    func resolveViolations(_ violationIds: [UUID]) async throws
    func deleteViolations(for workspaceId: UUID) async throws
    func getViolationCount(filter: ViolationFilter, workspaceId: UUID?) async throws -> Int
}

// MARK: - Errors

public enum ViolationStorageError: LocalizedError, Sendable {
    case databaseNotOpen
    case databaseOpenFailed(String)
    case sqlError(String)

    public var errorDescription: String? {
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

/// SQLite-based violation storage
/// Uses Swift concurrency actor for thread-safe database access
public actor ViolationStorageActor: ViolationStorageProtocol {

    // MARK: - Properties

    public let databasePath: URL
    public let useInMemory: Bool
    /// The SQLite connection. `SQLiteDatabase` owns the raw handle and closes it when
    /// released, so the actor needs no manual `deinit` and no `OpaquePointer` of its own.
    var database: SQLiteDatabase?

    // MARK: - Initialization

    public init(databasePath: URL? = nil, useInMemory: Bool = false) throws {
        self.useInMemory = useInMemory

        self.databasePath = try Self.resolveDatabasePath(databasePath: databasePath, useInMemory: useInMemory)
        let connection = try SQLiteDatabase.open(at: self.databasePath, useInMemory: useInMemory)
        try Self.createSchema(in: connection)
        self.database = connection
    }
}
