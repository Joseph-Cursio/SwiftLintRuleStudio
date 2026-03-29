//
//  WorkspaceManagerTestHelpers.swift
//  SwiftLintRuleStudioTests
//
//  Helper utilities for WorkspaceManager tests
//

import Foundation
@testable import SwiftLintRuleStudioCore

public enum WorkspaceManagerTestHelpers {
    public static func withWorkspaceManager<T: Sendable>(
        testName: String = #function,
        operation: @MainActor (WorkspaceManager) throws -> T
    ) async throws -> T {
        try await MainActor.run {
            let manager = WorkspaceManager.createForTesting(testName: testName)
            return try operation(manager)
        }
    }

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
