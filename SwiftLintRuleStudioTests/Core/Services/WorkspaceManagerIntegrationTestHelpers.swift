import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport

enum WorkspaceManagerIntegrationTestHelpers {
    static func withContainer<T: Sendable>(
        testName _: String = #function,
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

    static func createSwiftFile(in directory: URL, name: String, content: String) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
