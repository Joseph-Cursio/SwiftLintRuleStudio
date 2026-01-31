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

    static func createWorkspaceAnalyzer(
        swiftLintCLI: MockSwiftLintCLI,
        violationStorage: ViolationStorageProtocol,
        fileTracker: FileTracker? = nil
    ) async -> WorkspaceAnalyzer {
        nonisolated(unsafe) let cliCapture = swiftLintCLI
        nonisolated(unsafe) let storageCapture = violationStorage
        nonisolated(unsafe) let trackerCapture = fileTracker
        return await MainActor.run {
            WorkspaceAnalyzer(
                swiftLintCLI: cliCapture,
                violationStorage: storageCapture,
                fileTracker: trackerCapture
            )
        }
    }

    static func createViolationInspectorViewModel(
        violationStorage: ViolationStorageProtocol,
        workspaceAnalyzer: WorkspaceAnalyzer? = nil
    ) async -> ViolationInspectorViewModel {
        nonisolated(unsafe) let storageCapture = violationStorage
        nonisolated(unsafe) let analyzerCapture = workspaceAnalyzer
        return await MainActor.run {
            if let analyzer = analyzerCapture {
                return ViolationInspectorViewModel(violationStorage: storageCapture, workspaceAnalyzer: analyzer)
            }
            return ViolationInspectorViewModel(violationStorage: storageCapture)
        }
    }

    static func createSwiftFile(in directory: URL, name: String, content: String) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
