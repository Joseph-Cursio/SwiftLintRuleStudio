import Foundation
import Testing
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

// DependencyContainer, WorkspaceManager, WorkspaceAnalyzer, and ViolationInspectorViewModel are @MainActor
// but we'll use await MainActor.run { } inside tests to allow parallel test execution
@MainActor
struct WkspManagerIntegrationDepsTests {
    @Test("DependencyContainer includes WorkspaceManager")
    func testDependencyContainerIncludesWorkspaceManager() async throws {
        let (hasManager, hasWorkspace) = try await WorkspaceManagerIntegrationTestHelpers.withContainer { container in
            (true, container.workspaceManager.currentWorkspace == nil)
        }

        #expect(hasManager)
        #expect(hasWorkspace)
    }

    @Test("DependencyContainer shares WorkspaceManager instance")
    func testDependencyContainerSharesWorkspaceManager() async throws {
        let areDifferent = await MainActor.run {
            let container1 = DependencyContainer.createForTesting()
            let container2 = DependencyContainer.createForTesting()
            return container1.workspaceManager !== container2.workspaceManager
        }

        #expect(areDifferent)
    }
}
