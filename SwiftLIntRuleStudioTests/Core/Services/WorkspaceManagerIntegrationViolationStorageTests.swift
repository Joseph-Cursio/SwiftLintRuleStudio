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

        nonisolated(unsafe) let storage: ViolationStorage
        storage = try await Task.detached {
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

        let (count, hasRule1, hasRule2) = await MainActor.run {
            let count = fetched.count
            let hasRule1 = fetched.contains { $0.ruleID == "test_rule_1" }
            let hasRule2 = fetched.contains { $0.ruleID == "test_rule_2" }
            return (count, hasRule1, hasRule2)
        }
        #expect(count == 2)
        #expect(hasRule1 == true)
        #expect(hasRule2 == true)
    }

    @Test("ViolationStorage isolates violations by workspace")
    func testViolationStorageIsolatesByWorkspace() async throws {
        let tempDir1 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        let tempDir2 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer {
            WorkspaceTestHelpers.cleanupWorkspace(tempDir1)
            WorkspaceTestHelpers.cleanupWorkspace(tempDir2)
        }

        nonisolated(unsafe) let storage: ViolationStorage
        storage = try await Task.detached {
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

        let (count1, ruleID1, count2, ruleID2) = await MainActor.run {
            let count1 = workspace1Violations.count
            let ruleID1 = workspace1Violations[0].ruleID
            let count2 = workspace2Violations.count
            let ruleID2 = workspace2Violations[0].ruleID
            return (count1, ruleID1, count2, ruleID2)
        }
        #expect(count1 == 1)
        #expect(ruleID1 == "rule_1")
        #expect(count2 == 1)
        #expect(ruleID2 == "rule_2")
    }
}
