//
//  WorkspaceAnalyzerTestHelpers.swift
//  SwiftLIntRuleStudioTests
//
//  Helper utilities for WorkspaceAnalyzer tests
//

import Foundation
@testable import SwiftLIntRuleStudio

enum WorkspaceAnalyzerTestHelpers {
    static func withWorkspaceAnalyzer<T: Sendable>(
        swiftLintCLI: SwiftLintCLIProtocol,
        violationStorage: ViolationStorageProtocol,
        operation: @MainActor @escaping (WorkspaceAnalyzer) async throws -> T
    ) async throws -> T {
        return try await Task { @MainActor in
            let isolatedTracker = FileTracker.createForTesting()
            let analyzer = WorkspaceAnalyzer(swiftLintCLI: swiftLintCLI, violationStorage: violationStorage, fileTracker: isolatedTracker)
            return try await operation(analyzer)
        }.value
    }

    static func createMockSwiftLintCLI() -> MockSwiftLintCLI {
        MockSwiftLintCLI()
    }

    static func setupMockCLI(
        _ mockCLI: MockSwiftLintCLI,
        output: Data,
        shouldFail: Bool = false,
        shouldHang: Bool = false
    ) async {
        await mockCLI.setMockLintOutput(output)
        await mockCLI.setShouldHang(shouldHang)
    }

    static func createMockViolationStorage() -> MockViolationStorage {
        MockViolationStorage()
    }

    static func createTempWorkspace() async throws -> Workspace {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        return await MainActor.run {
            Workspace(path: tempDir)
        }
    }

    static func waitForAnalyzingState(
        _ analyzer: WorkspaceAnalyzer,
        expected: Bool,
        timeoutSeconds: TimeInterval = 0.2
    ) async -> Bool {
        await UIAsyncTestHelpers.waitForConditionAsync(timeout: timeoutSeconds, interval: 0.02) {
            await MainActor.run {
                analyzer.isAnalyzing == expected
            }
        }
    }

    static func cleanupTempWorkspace(_ workspace: Workspace) {
        try? FileManager.default.removeItem(at: workspace.path)
    }
}

// @unchecked Sendable: Test mock with controlled single-threaded access in tests
final class MockViolationStorage: ViolationStorageProtocol, @unchecked Sendable {
    var storedViolations: [Violation] = []

    func storeViolations(_ violations: [Violation], for workspaceId: UUID) async throws {
        await Task.yield()
        storedViolations = violations
    }

    func fetchViolations(filter: ViolationFilter, workspaceId: UUID?) async throws -> [Violation] {
        await Task.yield()
        return storedViolations
    }

    func getViolationCount(filter: ViolationFilter, workspaceId: UUID?) async throws -> Int {
        await Task.yield()
        return storedViolations.count
    }

    func suppressViolations(_ violationIds: [UUID], reason: String) async throws {
        await Task.yield()
    }

    func resolveViolations(_ violationIds: [UUID]) async throws {
        await Task.yield()
    }

    func deleteViolations(for workspaceId: UUID) async throws {
        await Task.yield()
    }
}
