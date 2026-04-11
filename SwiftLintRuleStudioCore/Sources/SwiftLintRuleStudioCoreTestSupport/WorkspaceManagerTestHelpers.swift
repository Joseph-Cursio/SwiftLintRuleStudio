//
//  WorkspaceManagerTestHelpers.swift
//  SwiftLintRuleStudioTests
//
//  Helper utilities for WorkspaceManager tests
//

import Foundation
@testable import SwiftLintRuleStudioCore

/// Test helpers for workspace manager tests
public enum WorkspaceManagerTestHelpers {
    /// Create an isolated workspace manager and run a synchronous operation
    public static func withWorkspaceManager<T: Sendable>(
        testName: String = #function,
        operation: @MainActor (WorkspaceManager) throws -> T
    ) async throws -> T {
        try await MainActor.run {
            let manager = WorkspaceManager.createForTesting(testName: testName)
            return try operation(manager)
        }
    }

    /// Create an isolated workspace manager and run an async operation
    public static func withWorkspaceManagerAsync<T: Sendable>(
        testName: String = #function,
        operation: @MainActor @escaping (WorkspaceManager) async throws -> T
    ) async throws -> T {
        try await Task { @MainActor in
            let manager = WorkspaceManager.createForTesting(testName: testName)
            return try await operation(manager)
        }.value
    }
}
