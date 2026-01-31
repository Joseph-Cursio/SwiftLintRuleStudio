import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// DependencyContainer, WorkspaceManager, WorkspaceAnalyzer, and ViolationInspectorViewModel are @MainActor
// but we'll use await MainActor.run { } inside tests to allow parallel test execution
struct WkspManagerIntegrationVITests {
    @Test("ViolationInspectorViewModel loads violations for current workspace")
    func testViolationInspectorViewModelLoadsForWorkspace() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        nonisolated(unsafe) let storage: ViolationStorage
        storage = try await Task.detached {
            try await ViolationStorage(useInMemory: true)
        }.value
        let viewModel = await MainActor.run {
            ViolationInspectorViewModel(violationStorage: storage)
        }

        let workspace = try await WorkspaceManagerIntegrationTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return try #require(manager.currentWorkspace)
        }

        let violations = [
            Violation(ruleID: "rule_1", filePath: "File1.swift", line: 10, severity: .error, message: "Error"),
            Violation(ruleID: "rule_2", filePath: "File2.swift", line: 20, severity: .warning, message: "Warning")
        ]
        try await storage.storeViolations(violations, for: workspace.id)

        try await viewModel.loadViolations(for: workspace.id)

        let (violationCount, totalCount, errorCount, warningCount) = await MainActor.run {
            (viewModel.violations.count, viewModel.violationCount, viewModel.errorCount, viewModel.warningCount)
        }

        #expect(violationCount == 2)
        #expect(totalCount == 2)
        #expect(errorCount == 1)
        #expect(warningCount == 1)
    }

    @Test("ViolationInspectorViewModel automatically analyzes workspace on load")
    func testViolationInspectorViewModelAutoAnalyzes() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        try WorkspaceManagerIntegrationTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let x = 1\n"
        )

        nonisolated(unsafe) let storage: ViolationStorage
        storage = try await Task.detached {
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

        nonisolated(unsafe) let cliCapture = mockCLI
        let viewModel = await MainActor.run {
            let isolatedTracker = FileTracker.createForTesting()
            let analyzer = WorkspaceAnalyzer(
                swiftLintCLI: cliCapture,
                violationStorage: storage,
                fileTracker: isolatedTracker
            )
            return ViolationInspectorViewModel(violationStorage: storage, workspaceAnalyzer: analyzer)
        }

        let workspace = try await WorkspaceManagerIntegrationTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return try #require(manager.currentWorkspace)
        }

        try await viewModel.loadViolations(for: workspace.id, workspace: workspace)

        let (violationCount, firstRuleID) = await MainActor.run {
            (viewModel.violations.count, viewModel.violations.first?.ruleID)
        }

        #expect(violationCount == 1)
        #expect(firstRuleID == "test_rule")
    }

    @Test("ViolationInspectorViewModel clears violations when workspace changes")
    func testViolationInspectorViewModelClearsOnWorkspaceChange() async throws {
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
        let viewModel = await MainActor.run {
            ViolationInspectorViewModel(violationStorage: storage)
        }

        let workspace1 = try await WorkspaceManagerIntegrationTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir1)
            return try #require(manager.currentWorkspace)
        }

        let violations1 = [
            Violation(ruleID: "rule_1", filePath: "File1.swift", line: 10, severity: .error, message: "Error")
        ]
        try await storage.storeViolations(violations1, for: workspace1.id)
        try await viewModel.loadViolations(for: workspace1.id)

        let count1 = await MainActor.run { viewModel.violations.count }
        #expect(count1 == 1)

        let workspace2 = try await WorkspaceManagerIntegrationTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir2)
            return try #require(manager.currentWorkspace)
        }

        await viewModel.clearViolations()

        let (isEmpty, countAfterClear) = await MainActor.run {
            (viewModel.violations.isEmpty, viewModel.violationCount)
        }
        #expect(isEmpty == true)
        #expect(countAfterClear == 0)

        let violations2 = [
            Violation(ruleID: "rule_2", filePath: "File2.swift", line: 20, severity: .warning, message: "Warning")
        ]
        try await storage.storeViolations(violations2, for: workspace2.id)
        try await viewModel.loadViolations(for: workspace2.id)

        let (count2, ruleID) = await MainActor.run {
            (viewModel.violations.count, viewModel.violations[0].ruleID)
        }
        #expect(count2 == 1)
        #expect(ruleID == "rule_2")
    }
}
