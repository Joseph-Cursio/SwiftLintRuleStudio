import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// DependencyContainer, WorkspaceManager, WorkspaceAnalyzer, and ViolationInspectorViewModel are @MainActor
// but we'll use await MainActor.run { } inside tests to allow parallel test execution
struct WkspManagerIntegrationStorageTests {
    @Test("WorkspaceManager works with ViolationStorage")
    func testWorkspaceManagerWithViolationStorage() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let storage = try await Task.detached {
            try await ViolationStorage(useInMemory: true)
        }.value

        let workspace = try await WorkspaceManagerIntegrationTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return try #require(manager.currentWorkspace)
        }

        let violation1 = Violation(
            ruleID: "test_rule_1",
            filePath: "Test1.swift",
            line: 10,
            column: 5,
            severity: .error,
            message: "Test violation 1"
        )

        let violation2 = Violation(
            ruleID: "test_rule_2",
            filePath: "Test2.swift",
            line: 20,
            column: 10,
            severity: .warning,
            message: "Test violation 2"
        )

        try await storage.storeViolations([violation1, violation2], for: workspace.id)

        let filter = ViolationFilter()
        let fetched = try await storage.fetchViolations(filter: filter, workspaceId: workspace.id)

        #expect(fetched.count == 2)
        #expect(fetched.contains { $0.ruleID == "test_rule_1" } == true)
        #expect(fetched.contains { $0.ruleID == "test_rule_2" } == true)
    }

    @Test("ViolationStorage isolates violations by workspace")
    func testViolationStorageIsolatesByWorkspace() async throws {
        let tempDir1 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        let tempDir2 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer {
            WorkspaceTestHelpers.cleanupWorkspace(tempDir1)
            WorkspaceTestHelpers.cleanupWorkspace(tempDir2)
        }

        let storage = try await Task.detached {
            try await ViolationStorage(useInMemory: true)
        }.value

        let workspace1 = try await WorkspaceManagerIntegrationTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir1)
            return try #require(manager.currentWorkspace)
        }

        let violation1 = Violation(
            ruleID: "rule_1",
            filePath: "File1.swift",
            line: 10,
            severity: .error,
            message: "Violation 1"
        )
        try await storage.storeViolations([violation1], for: workspace1.id)

        let workspace2 = try await WorkspaceManagerIntegrationTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir2)
            return try #require(manager.currentWorkspace)
        }

        let violation2 = Violation(
            ruleID: "rule_2",
            filePath: "File2.swift",
            line: 20,
            severity: .warning,
            message: "Violation 2"
        )
        try await storage.storeViolations([violation2], for: workspace2.id)

        let filter = ViolationFilter()
        let workspace1Violations = try await storage.fetchViolations(filter: filter, workspaceId: workspace1.id)
        let workspace2Violations = try await storage.fetchViolations(filter: filter, workspaceId: workspace2.id)

        #expect(workspace1Violations.count == 1)
        #expect(workspace1Violations[0].ruleID == "rule_1")
        #expect(workspace2Violations.count == 1)
        #expect(workspace2Violations[0].ruleID == "rule_2")
    }
}
