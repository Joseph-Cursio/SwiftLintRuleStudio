//
//  WorkspaceAnalyzerTestHelpers.swift
//  SwiftLintRuleStudioTests
//
//  Helper utilities for WorkspaceAnalyzer tests
//

import Foundation
@testable import SwiftLintRuleStudioCore

/// Test helpers for workspace analyzer tests
public enum WorkspaceAnalyzerTestHelpers {
    /// Create a temporary workspace analyzer and run an operation against it
    public static func withWorkspaceAnalyzer<T: Sendable>(
        swiftLintCLI: SwiftLintCLIProtocol,
        violationStorage: ViolationStorageProtocol,
        operation: @MainActor @escaping (WorkspaceAnalyzer) async throws -> T
    ) async throws -> T {
        return try await Task { @MainActor in
            let isolatedTracker = FileTracker.createForTesting()
            let analyzer = WorkspaceAnalyzer(
                swiftLintCLI: swiftLintCLI,
                violationStorage: violationStorage,
                fileTracker: isolatedTracker)
            return try await operation(analyzer)
        }.value
    }

    /// Create a mock SwiftLint CLI actor with default configuration
    public static func createMockSwiftLintCLIActor() -> MockSwiftLintCLIActor {
        MockSwiftLintCLIActor()
    }

    /// Configure a mock CLI actor with output and behavior options
    public static func setupMockCLI(
        _ mockCLI: MockSwiftLintCLIActor,
        output: Data,
        shouldFail: Bool = false,
        shouldHang: Bool = false
    ) async {
        await mockCLI.setMockLintOutput(output)
        await mockCLI.setShouldHang(shouldHang)
    }

    /// Create a mock violation storage for testing
    public static func createMockViolationStorage() -> MockViolationStorage {
        MockViolationStorage()
    }

    /// Create a temporary workspace directory for testing
    public static func createTempWorkspace() async throws -> Workspace {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        return await MainActor.run {
            Workspace(path: tempDir)
        }
    }

    /// Poll until the analyzer reaches the expected analyzing state or timeout
    public static func waitForAnalyzingState(
        _ analyzer: WorkspaceAnalyzer,
        expected: Bool,
        timeoutSeconds: TimeInterval = 0.2
    ) async -> Bool {
        let startTime = Date.now
        while Date.now.timeIntervalSince(startTime) < timeoutSeconds {
            let current = await MainActor.run { analyzer.isAnalyzing }
            if current == expected { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }

    /// Remove a temporary workspace directory
    public static func cleanupTempWorkspace(_ workspace: Workspace) {
        try? FileManager.default.removeItem(at: workspace.path)
    }
}

// @unchecked Sendable: Test mock with controlled single-threaded access in tests
public final class MockViolationStorage: ViolationStorageProtocol, @unchecked Sendable {
    public var storedViolations: [Violation] = []

    public func storeViolations(_ violations: [Violation], for workspaceId: UUID) async throws {
        await Task.yield()
        storedViolations = violations
    }

    public func fetchViolations(filter: ViolationFilter, workspaceId: UUID?) async throws -> [Violation] {
        await Task.yield()
        return storedViolations
    }

    public func getViolationCount(filter: ViolationFilter, workspaceId: UUID?) async throws -> Int {
        await Task.yield()
        return storedViolations.count
    }

    public func suppressViolations(_ violationIds: [UUID], reason: String) async throws {
        await Task.yield()
    }

    public func resolveViolations(_ violationIds: [UUID]) async throws {
        await Task.yield()
    }

    public func deleteViolations(for workspaceId: UUID) async throws {
        await Task.yield()
    }
}
