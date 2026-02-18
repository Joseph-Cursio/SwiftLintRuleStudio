import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// DependencyContainer, WorkspaceManager, WorkspaceAnalyzer, and ViolationInspectorViewModel are @MainActor
// but we'll use await MainActor.run { } inside tests to allow parallel test execution
struct WkspManagerIntegrationAnalyzerTests {
    @Test("WorkspaceAnalyzer analyzes current workspace")
    func testWorkspaceAnalyzerAnalyzesCurrentWorkspace() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        try WorkspaceManagerIntegrationTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let x = 1\n"
        )

        let storage = try await Task.detached {
            try await ViolationStorage(useInMemory: true)
        }.value
        let mockCLI = MockSwiftLintCLI()

        let mockViolationsJSON = Data("""
        [
          {
            "rule_id": "test_rule",
            "reason": "Test violation",
            "file": "Test.swift",
            "line": 1,
            "severity": "error"
          }
        ]
        """.utf8)
        await mockCLI.setMockLintOutput(mockViolationsJSON)

        let analyzer = await MainActor.run {
            WorkspaceAnalyzer(
                swiftLintCLI: mockCLI,
                violationStorage: storage,
                fileTracker: nil
            )
        }

        let workspace = try await WorkspaceManagerIntegrationTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return try #require(manager.currentWorkspace)
        }

        let result = try await analyzer.analyze(workspace: workspace)

        let (violationCount, ruleID, filesAnalyzed) = await MainActor.run {
            let count = result.violations.count
            let ruleID = result.violations[0].ruleID
            let filesAnalyzed = result.filesAnalyzed
            return (count, ruleID, filesAnalyzed)
        }
        #expect(violationCount == 1)
        #expect(ruleID == "test_rule")
        #expect(filesAnalyzed == 1)

        let filter = ViolationFilter()
        let stored = try await storage.fetchViolations(filter: filter, workspaceId: workspace.id)
        #expect(stored.count == 1)
    }
}
