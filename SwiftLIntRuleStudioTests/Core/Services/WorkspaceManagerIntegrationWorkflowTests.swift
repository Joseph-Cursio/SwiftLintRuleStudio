import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// DependencyContainer, WorkspaceManager, WorkspaceAnalyzer, and ViolationInspectorViewModel are @MainActor
// but we'll use await MainActor.run { } inside tests to allow parallel test execution
struct WorkspaceManagerIntegrationWorkflowTests {
    @Test("Complete workflow: open workspace -> analyze -> view violations")
    func testCompleteWorkflow() async throws {
        let tempDir = try createWorkspaceWithFiles()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let storage = try await createInMemoryStorage()
        let mockCLI = MockSwiftLintCLI()
        await configureMockViolations(mockCLI: mockCLI)

        let analyzer = await createAnalyzer(storage: storage, mockCLI: mockCLI)
        let viewModel = await createViewModel(storage: storage, analyzer: analyzer)

        let (workspace, recentCount) = try await openWorkspace(at: tempDir)
        #expect(recentCount == 1)

        let analysisResult = try await analyzer.analyze(workspace: workspace)
        let (violationCount, filesAnalyzed) = await MainActor.run {
            (analysisResult.violations.count, analysisResult.filesAnalyzed)
        }
        #expect(violationCount == 2)
        #expect(filesAnalyzed == 2)

        try await viewModel.loadViolations(for: workspace.id)
        let (loadedViolationCount, errorCount, warningCount) = await MainActor.run {
            (viewModel.violations.count, viewModel.errorCount, viewModel.warningCount)
        }
        #expect(loadedViolationCount == 2)
        #expect(errorCount == 1)
        #expect(warningCount == 1)

        let (filteredCount, filteredSeverity) = await MainActor.run {
            viewModel.selectedSeverities = [.error]
            return (viewModel.filteredViolations.count, viewModel.filteredViolations[0].severity)
        }
        #expect(filteredCount == 1)
        #expect(filteredSeverity == .error)

        let hasWorkspace = try await WorkspaceManagerIntegrationTestHelpers.withWorkspaceManager { manager in
            manager.closeWorkspace()
            return manager.currentWorkspace == nil
        }
        #expect(hasWorkspace == true)

        await viewModel.clearViolations()
        let isEmpty = await MainActor.run { viewModel.violations.isEmpty }
        #expect(isEmpty == true)
    }

    @Test("Workspace persistence across app restarts")
    func testWorkspacePersistenceAcrossRestarts() async throws {
        let sharedDefaults = IsolatedUserDefaults.createShared(for: "WorkspaceManagerIntegrationTests")
        defer {
            IsolatedUserDefaults.cleanup(sharedDefaults)
        }

        sharedDefaults.removeObject(forKey: "SwiftLintRuleStudio.recentWorkspaces")

        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let (workspace1, workspaceId) = try await MainActor.run {
            let manager1 = WorkspaceManager(userDefaults: sharedDefaults)
            try manager1.openWorkspace(at: tempDir)
            let workspace1 = try #require(manager1.currentWorkspace)
            return (workspace1, workspace1.id)
        }

        let storage = try await createInMemoryStorage()
        let violations = [
            Violation(ruleID: "rule_1", filePath: "File1.swift", line: 10, severity: .error, message: "Error")
        ]
        try await storage.storeViolations(violations, for: workspaceId)

        let (recentCount, firstPath, workspace2) = try await MainActor.run {
            let manager2 = WorkspaceManager(userDefaults: sharedDefaults)
            let recentCount = manager2.recentWorkspaces.count
            let firstPath = manager2.recentWorkspaces.first?.path
            try manager2.openWorkspace(at: tempDir)
            let workspace2 = try #require(manager2.currentWorkspace)
            return (recentCount, firstPath, workspace2)
        }

        #expect(recentCount == 1)
        #expect(firstPath == tempDir)

        #expect(workspace2.path == tempDir)

        let filter = ViolationFilter()
        let stored = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)
        #expect(stored.count == 1)
        _ = workspace1 // keep for clarity about stored violations
    }

    private func createWorkspaceWithFiles() throws -> URL {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        try WorkspaceManagerIntegrationTestHelpers.createSwiftFile(
            in: tempDir,
            name: "File1.swift",
            content: "let x = 1\nlet y = 2\n"
        )
        try WorkspaceManagerIntegrationTestHelpers.createSwiftFile(
            in: tempDir,
            name: "File2.swift",
            content: "let z = 3\n"
        )
        return tempDir
    }

    private func createInMemoryStorage() async throws -> ViolationStorage {
        let storage = try await Task.detached {
            try await ViolationStorage(useInMemory: true)
        }.value
        return storage
    }

    private func configureMockViolations(mockCLI: MockSwiftLintCLI) async {
        let mockViolationsJSON = Data("""
        [
          {
            "rule_id": "rule_1",
            "reason": "Violation 1",
            "file": "File1.swift",
            "line": 1,
            "severity": "error"
          },
          {
            "rule_id": "rule_2",
            "reason": "Violation 2",
            "file": "File2.swift",
            "line": 1,
            "severity": "warning"
          }
        ]
        """.utf8)
        await mockCLI.setMockLintOutput(mockViolationsJSON)
    }

    private func createAnalyzer(
        storage: ViolationStorage,
        mockCLI: MockSwiftLintCLI
    ) async -> WorkspaceAnalyzer {
        return await MainActor.run {
            WorkspaceAnalyzer(
                swiftLintCLI: mockCLI,
                violationStorage: storage,
                fileTracker: nil
            )
        }
    }

    private func createViewModel(
        storage: ViolationStorage,
        analyzer: WorkspaceAnalyzer
    ) async -> ViolationInspectorViewModel {
        await MainActor.run {
            ViolationInspectorViewModel(violationStorage: storage, workspaceAnalyzer: analyzer)
        }
    }

    private func openWorkspace(at tempDir: URL) async throws -> (Workspace, Int) {
        try await WorkspaceManagerIntegrationTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            let workspace = try #require(manager.currentWorkspace)
            return (workspace, manager.recentWorkspaces.count)
        }
    }
}
