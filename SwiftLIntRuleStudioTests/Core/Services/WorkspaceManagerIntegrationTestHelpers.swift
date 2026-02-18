import Foundation
@testable import SwiftLIntRuleStudio

enum WorkspaceManagerIntegrationTestHelpers {
    static func withContainer<T: Sendable>(
        testName: String = #function,
        operation: @MainActor (DependencyContainer) throws -> T
    ) async throws -> T {
        try await MainActor.run {
            let container = DependencyContainer.createForTesting()
            return try operation(container)
        }
    }

    static func withWorkspaceManager<T: Sendable>(
        testName: String = #function,
        operation: @MainActor (WorkspaceManager) throws -> T
    ) async throws -> T {
        try await MainActor.run {
            let manager = WorkspaceManager.createForTesting(testName: testName)
            return try operation(manager)
        }
    }

    static func withWorkspaceManagerAsync<T: Sendable>(
        testName: String = #function,
        operation: @MainActor @escaping (WorkspaceManager) async throws -> T
    ) async throws -> T {
        try await Task { @MainActor in
            let manager = WorkspaceManager.createForTesting(testName: testName)
            return try await operation(manager)
        }.value
    }

    @MainActor
    static func createWorkspaceAnalyzer(
        swiftLintCLI: MockSwiftLintCLI,
        violationStorage: ViolationStorageProtocol,
        fileTracker: sending FileTracker? = nil
    ) -> WorkspaceAnalyzer {
        WorkspaceAnalyzer(swiftLintCLI: swiftLintCLI, violationStorage: violationStorage, fileTracker: fileTracker)
    }

    static func createViolationInspectorViewModel(
        violationStorage: ViolationStorageProtocol,
        workspaceAnalyzer: WorkspaceAnalyzer? = nil
    ) async -> ViolationInspectorViewModel {
        return await MainActor.run {
            if let analyzer = workspaceAnalyzer {
                return ViolationInspectorViewModel(violationStorage: violationStorage, workspaceAnalyzer: analyzer)
            }
            return ViolationInspectorViewModel(violationStorage: violationStorage)
        }
    }

    static func createSwiftFile(in directory: URL, name: String, content: String) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
