import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// DependencyContainer, WorkspaceManager, WorkspaceAnalyzer, and ViolationInspectorViewModel are @MainActor
// but we'll use await MainActor.run { } inside tests to allow parallel test execution
struct WkspManagerIntegrationErrorTests {
    @Test("Handles workspace deletion gracefully")
    func testHandlesWorkspaceDeletion() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()

        let (hasWorkspace, recentCount) = try await WorkspaceManagerIntegrationTestHelpers
            .withWorkspaceManager { manager in
                try manager.openWorkspace(at: tempDir)
                return (manager.currentWorkspace != nil, manager.recentWorkspaces.count)
            }

        #expect(hasWorkspace == true)
        #expect(recentCount == 1)

        WorkspaceTestHelpers.cleanupWorkspace(tempDir)

        let isEmpty = try await WorkspaceManagerIntegrationTestHelpers.withWorkspaceManager { newManager in
            newManager.recentWorkspaces.isEmpty
        }
        #expect(isEmpty == true)
    }

    @Test("Handles invalid workspace paths in recent workspaces")
    func testHandlesInvalidPathsInRecentWorkspaces() async throws {
        let tempDir1 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        let tempDir2 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer {
            WorkspaceTestHelpers.cleanupWorkspace(tempDir1)
            WorkspaceTestHelpers.cleanupWorkspace(tempDir2)
        }

        let (recentCount1, recentCount2, firstPath) = try await MainActor.run {
            let sharedDefaults = IsolatedUserDefaults.createShared(for: #function)

            let manager1 = WorkspaceManager(userDefaults: sharedDefaults)
            try manager1.openWorkspace(at: tempDir1)
            try manager1.openWorkspace(at: tempDir2)
            let recentCount1 = manager1.recentWorkspaces.count

            WorkspaceTestHelpers.cleanupWorkspace(tempDir1)

            let manager2 = WorkspaceManager(userDefaults: sharedDefaults)
            let recentCount2 = manager2.recentWorkspaces.count
            let firstPath = manager2.recentWorkspaces.first?.path
            return (recentCount1, recentCount2, firstPath)
        }

        #expect(recentCount1 == 2)
        #expect(recentCount2 == 1)
        #expect(firstPath == tempDir2)
    }
}
