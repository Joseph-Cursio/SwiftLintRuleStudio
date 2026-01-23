//
//  WorkspaceManagerIntegrationTests.swift
//  SwiftLintRuleStudioTests
//
//  Integration tests for WorkspaceManager with other components
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// DependencyContainer, WorkspaceManager, WorkspaceAnalyzer, and ViolationInspectorViewModel are @MainActor
// but we'll use await MainActor.run { } inside tests to allow parallel test execution
struct WorkspaceManagerIntegrationTests {
    
    // Helper to access DependencyContainer on MainActor with isolated UserDefaults
    private func withContainer<T: Sendable>(
        testName: String = #function,
        operation: @MainActor (DependencyContainer) throws -> T
    ) async throws -> T {
        try await MainActor.run {
            let container = DependencyContainer.createForTesting()
            return try operation(container)
        }
    }
    
    // Helper to run WorkspaceManager operations on MainActor with isolated UserDefaults
    private func withWorkspaceManager<T: Sendable>(
        testName: String = #function,
        operation: @MainActor (WorkspaceManager) throws -> T
    ) async throws -> T {
        try await MainActor.run {
            let manager = WorkspaceManager.createForTesting(testName: testName)
            return try operation(manager)
        }
    }
    
    // Helper to run WorkspaceManager async operations on MainActor with isolated UserDefaults
    private func withWorkspaceManagerAsync<T: Sendable>(
        testName: String = #function,
        operation: @MainActor @escaping (WorkspaceManager) async throws -> T
    ) async throws -> T {
        return try await Task { @MainActor in
            let manager = WorkspaceManager.createForTesting(testName: testName)
            return try await operation(manager)
        }.value
    }
    
    // Helper to create WorkspaceAnalyzer on MainActor
    private func createWorkspaceAnalyzer(
        swiftLintCLI: MockSwiftLintCLI,
        violationStorage: ViolationStorageProtocol,
        fileTracker: FileTracker? = nil
    ) async -> WorkspaceAnalyzer {
        // Capture with nonisolated(unsafe) to bypass Sendable check for test mocks
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
    
    // Helper to create ViolationInspectorViewModel on MainActor
    private func createViolationInspectorViewModel(
        violationStorage: ViolationStorageProtocol,
        workspaceAnalyzer: WorkspaceAnalyzer? = nil
    ) async -> ViolationInspectorViewModel {
        nonisolated(unsafe) let storageCapture = violationStorage
        nonisolated(unsafe) let analyzerCapture = workspaceAnalyzer
        return await MainActor.run {
            if let analyzer = analyzerCapture {
                return ViolationInspectorViewModel(violationStorage: storageCapture, workspaceAnalyzer: analyzer)
            } else {
                return ViolationInspectorViewModel(violationStorage: storageCapture)
            }
        }
    }
    
    // MARK: - Test Helpers
    
    // Use WorkspaceTestHelpers for creating valid Swift workspaces
    // This ensures WorkspaceManager validation passes
    
    private func createSwiftFile(in directory: URL, name: String, content: String) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    // MARK: - DependencyContainer Integration Tests
    
    @Test("DependencyContainer includes WorkspaceManager")
    func testDependencyContainerIncludesWorkspaceManager() async throws {
        let (hasManager, hasWorkspace) = try await withContainer { container in
            return (container.workspaceManager != nil, container.workspaceManager.currentWorkspace == nil)
        }
        
        #expect(hasManager == true)
        #expect(hasWorkspace == true)
    }
    
    @Test("DependencyContainer shares WorkspaceManager instance")
    func testDependencyContainerSharesWorkspaceManager() async throws {
        let areDifferent = try await MainActor.run {
            let container1 = DependencyContainer.createForTesting()
            let container2 = DependencyContainer.createForTesting()
            
            // They should have separate instances (not shared)
            return container1.workspaceManager !== container2.workspaceManager
        }
        
        #expect(areDifferent == true)
    }
    
    // MARK: - WorkspaceManager + ViolationStorage Integration
    
    @Test("WorkspaceManager works with ViolationStorage")
    func testWorkspaceManagerWithViolationStorage() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        // ViolationStorage is an actor, not @MainActor, but Swift 6 has false positive
        // Work around by creating it in a nonisolated context and capturing with nonisolated(unsafe)
        nonisolated(unsafe) let storage: ViolationStorage
        storage = try await Task.detached {
            try await ViolationStorage(useInMemory: true)
        }.value
        
        // Open workspace
        let workspace = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return try #require(manager.currentWorkspace)
        }
        
        // Create test violations
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
        
        // Store violations for workspace
        try await storage.storeViolations([violation1, violation2], for: workspace.id)
        
        // Fetch violations
        let filter = ViolationFilter()
        let fetched = try await storage.fetchViolations(filter: filter, workspaceId: workspace.id)
        
        // Extract ruleIDs inside MainActor context to avoid isolation errors
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
        
        // ViolationStorage is an actor, not @MainActor, but Swift 6 has false positive
        // Work around by creating it in a nonisolated context and capturing with nonisolated(unsafe)
        nonisolated(unsafe) let storage: ViolationStorage
        storage = try await Task.detached {
            try await ViolationStorage(useInMemory: true)
        }.value
        
        // Open first workspace and add violations
        let workspace1 = try await withWorkspaceManager { manager in
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
        
        // Open second workspace and add different violations
        let workspace2 = try await withWorkspaceManager { manager in
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
        
        // Verify isolation
        let filter = ViolationFilter()
        let workspace1Violations = try await storage.fetchViolations(filter: filter, workspaceId: workspace1.id)
        let workspace2Violations = try await storage.fetchViolations(filter: filter, workspaceId: workspace2.id)
        
        // Extract ruleIDs inside MainActor context
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
    
    // MARK: - WorkspaceManager + ViolationInspectorViewModel Integration
    
    @Test("ViolationInspectorViewModel loads violations for current workspace")
    func testViolationInspectorViewModelLoadsForWorkspace() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        // ViolationStorage is an actor, not @MainActor, but Swift 6 has false positive
        // Work around by creating it in a nonisolated context and capturing with nonisolated(unsafe)
        nonisolated(unsafe) let storage: ViolationStorage
        storage = try await Task.detached {
            try await ViolationStorage(useInMemory: true)
        }.value
        // Workaround: Create view model directly in MainActor.run to bypass protocol conformance false positive
        let viewModel = await MainActor.run {
            ViolationInspectorViewModel(violationStorage: storage)
        }
        
        // Open workspace
        let workspace = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return try #require(manager.currentWorkspace)
        }
        
        // Add violations
        let violations = [
            Violation(ruleID: "rule_1", filePath: "File1.swift", line: 10, severity: .error, message: "Error"),
            Violation(ruleID: "rule_2", filePath: "File2.swift", line: 20, severity: .warning, message: "Warning")
        ]
        try await storage.storeViolations(violations, for: workspace.id)
        
        // Load violations in view model (without analyzer, should still work)
        try await viewModel.loadViolations(for: workspace.id)
        
        let (violationCount, totalCount, errorCount, warningCount) = await MainActor.run {
            return (viewModel.violations.count, viewModel.violationCount, viewModel.errorCount, viewModel.warningCount)
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
        
        // Create a Swift file in the workspace
        try createSwiftFile(in: tempDir, name: "Test.swift", content: "let x = 1\n")
        
        // ViolationStorage is an actor, not @MainActor, but Swift 6 has false positive
        // Work around by creating it in a nonisolated context and capturing with nonisolated(unsafe)
        nonisolated(unsafe) let storage: ViolationStorage
        storage = try await Task.detached {
            try await ViolationStorage(useInMemory: true)
        }.value
        let mockCLI = MockSwiftLintCLI()
        
        // Setup mock to return violations
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
        
        // Workaround: Create analyzer and view model directly in MainActor.run to bypass protocol conformance false positive
        nonisolated(unsafe) let cliCapture = mockCLI
        let (analyzer, viewModel) = await MainActor.run {
            let isolatedTracker = FileTracker.createForTesting()
            let analyzer = WorkspaceAnalyzer(
                swiftLintCLI: cliCapture,
                violationStorage: storage,
                fileTracker: isolatedTracker
            )
            let viewModel = ViolationInspectorViewModel(
                violationStorage: storage,
                workspaceAnalyzer: analyzer
            )
            return (analyzer, viewModel)
        }
        
        // Open workspace
        let workspace = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return try #require(manager.currentWorkspace)
        }
        
        // Load violations - should automatically trigger analysis
        try await viewModel.loadViolations(for: workspace.id, workspace: workspace)
        
        // Should have violations from analysis
        let (violationCount, firstRuleID) = await MainActor.run {
            return (viewModel.violations.count, viewModel.violations.first?.ruleID)
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
        
        // ViolationStorage is an actor, not @MainActor, but Swift 6 has false positive
        // Work around by creating it in a nonisolated context and capturing with nonisolated(unsafe)
        nonisolated(unsafe) let storage: ViolationStorage
        storage = try await Task.detached {
            try await ViolationStorage(useInMemory: true)
        }.value
        // Workaround: Create view model directly in MainActor.run to bypass protocol conformance false positive
        let viewModel = await MainActor.run {
            ViolationInspectorViewModel(violationStorage: storage)
        }
        
        // Open first workspace and load violations
        let workspace1 = try await withWorkspaceManager { manager in
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
        
        // Switch to second workspace
        let workspace2 = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir2)
            return try #require(manager.currentWorkspace)
        }
        
        // Clear violations (simulating workspace change)
        await viewModel.clearViolations()
        
        let (isEmpty, countAfterClear) = await MainActor.run {
            return (viewModel.violations.isEmpty, viewModel.violationCount)
        }
        #expect(isEmpty == true)
        #expect(countAfterClear == 0)
        
        // Load violations for new workspace
        let violations2 = [
            Violation(ruleID: "rule_2", filePath: "File2.swift", line: 20, severity: .warning, message: "Warning")
        ]
        try await storage.storeViolations(violations2, for: workspace2.id)
        try await viewModel.loadViolations(for: workspace2.id)
        
        let (count2, ruleID) = await MainActor.run {
            return (viewModel.violations.count, viewModel.violations[0].ruleID)
        }
        #expect(count2 == 1)
        #expect(ruleID == "rule_2")
    }
    
    // MARK: - WorkspaceManager + WorkspaceAnalyzer Integration
    
    @Test("WorkspaceAnalyzer analyzes current workspace")
    func testWorkspaceAnalyzerAnalyzesCurrentWorkspace() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        // Create a Swift file in the workspace
        try createSwiftFile(in: tempDir, name: "Test.swift", content: "let x = 1\n")
        
        // ViolationStorage is an actor, not @MainActor, but Swift 6 has false positive
        // Work around by creating it in a nonisolated context and capturing with nonisolated(unsafe)
        nonisolated(unsafe) let storage: ViolationStorage
        storage = try await Task.detached {
            try await ViolationStorage(useInMemory: true)
        }.value
        let mockCLI = MockSwiftLintCLI()
        
        // Setup mock to return violations
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
        
        // Workaround: Create analyzer directly in MainActor.run to bypass protocol conformance false positive
        nonisolated(unsafe) let cliCapture1 = mockCLI
        let analyzer = await MainActor.run {
            WorkspaceAnalyzer(
                swiftLintCLI: cliCapture1,
                violationStorage: storage,
                fileTracker: nil
            )
        }
        
        // Open workspace
        let workspace = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return try #require(manager.currentWorkspace)
        }
        
        // Analyze workspace
        let result = try await analyzer.analyze(workspace: workspace)
        
        // Extract properties inside MainActor context
        let (violationCount, ruleID, filesAnalyzed) = await MainActor.run {
            let count = result.violations.count
            let ruleID = result.violations[0].ruleID
            let filesAnalyzed = result.filesAnalyzed
            return (count, ruleID, filesAnalyzed)
        }
        #expect(violationCount == 1)
        #expect(ruleID == "test_rule")
        #expect(filesAnalyzed == 1)
        
        // Verify violations were stored
        let filter = ViolationFilter()
        let stored = try await storage.fetchViolations(filter: filter, workspaceId: workspace.id)
        #expect(stored.count == 1)
    }
    
    // MARK: - Full Workflow Integration Tests
    
    @Test("Complete workflow: open workspace -> analyze -> view violations")
    func testCompleteWorkflow() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        // Create Swift files
        try createSwiftFile(in: tempDir, name: "File1.swift", content: "let x = 1\nlet y = 2\n")
        try createSwiftFile(in: tempDir, name: "File2.swift", content: "let z = 3\n")
        
        // Setup components
        // ViolationStorage is an actor, not @MainActor, but Swift 6 has false positive
        // Work around by creating it in a nonisolated context and capturing with nonisolated(unsafe)
        nonisolated(unsafe) let storage: ViolationStorage
        storage = try await Task.detached {
            try await ViolationStorage(useInMemory: true)
        }.value
        let mockCLI = MockSwiftLintCLI()
        
        // Setup mock violations
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
        
        // Workaround: Create analyzer directly in MainActor.run to bypass protocol conformance false positive
        nonisolated(unsafe) let cliCapture2 = mockCLI
        let analyzer = await MainActor.run {
            WorkspaceAnalyzer(
                swiftLintCLI: cliCapture2,
                violationStorage: storage,
                fileTracker: nil
            )
        }
        // Workaround: Create view model directly in MainActor.run to bypass protocol conformance false positive
        let viewModel = await MainActor.run {
            ViolationInspectorViewModel(violationStorage: storage, workspaceAnalyzer: analyzer)
        }
        
        // Step 1: Open workspace
        let (workspace, recentCount) = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            let workspace = try #require(manager.currentWorkspace)
            return (workspace, manager.recentWorkspaces.count)
        }
        #expect(recentCount == 1)
        
        // Step 2: Analyze workspace
        let analysisResult = try await analyzer.analyze(workspace: workspace)
        let (violationCount, filesAnalyzed) = await MainActor.run {
            (analysisResult.violations.count, analysisResult.filesAnalyzed)
        }
        #expect(violationCount == 2)
        #expect(filesAnalyzed == 2)
        
        // Step 3: Load violations in view model
        try await viewModel.loadViolations(for: workspace.id)
        let (loadedViolationCount, errorCount, warningCount) = await MainActor.run {
            return (viewModel.violations.count, viewModel.errorCount, viewModel.warningCount)
        }
        #expect(loadedViolationCount == 2)
        #expect(errorCount == 1)
        #expect(warningCount == 1)
        
        // Step 4: Filter violations
        let (filteredCount, filteredSeverity) = await MainActor.run {
            viewModel.selectedSeverities = [.error]
            return (viewModel.filteredViolations.count, viewModel.filteredViolations[0].severity)
        }
        #expect(filteredCount == 1)
        #expect(filteredSeverity == .error)
        
        // Step 5: Close workspace
        let hasWorkspace = try await withWorkspaceManager { manager in
            manager.closeWorkspace()
            return manager.currentWorkspace == nil
        }
        #expect(hasWorkspace == true)
        
        // Step 6: Clear violations
        await viewModel.clearViolations()
        let isEmpty = await MainActor.run { viewModel.violations.isEmpty }
        #expect(isEmpty == true)
    }
    
    @Test("Workspace persistence across app restarts")
    func testWorkspacePersistenceAcrossRestarts() async throws {
        // Use shared isolated UserDefaults for this test to simulate persistence across restarts
        // Both manager instances need to use the same UserDefaults
        let sharedDefaults = IsolatedUserDefaults.createShared(for: "WorkspaceManagerIntegrationTests")
        defer {
            IsolatedUserDefaults.cleanup(sharedDefaults)
        }
        
        // Capture with nonisolated(unsafe) to avoid Sendable warnings
        // UserDefaults is thread-safe for our test use case
        nonisolated(unsafe) let defaultsCapture = sharedDefaults
        sharedDefaults.removeObject(forKey: "SwiftLintRuleStudio.recentWorkspaces")
        
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        // Create first manager instance and open workspace
        let (workspace1, workspaceId) = try await MainActor.run {
            let manager1 = WorkspaceManager(userDefaults: defaultsCapture)
            try manager1.openWorkspace(at: tempDir)
            let workspace1 = try #require(manager1.currentWorkspace)
            return (workspace1, workspace1.id)
        }
        
        // Store some violations
        // ViolationStorage is an actor, not @MainActor, but Swift 6 has false positive
        // Work around by creating it in a nonisolated context and capturing with nonisolated(unsafe)
        nonisolated(unsafe) let storage: ViolationStorage
        storage = try await Task.detached {
            try await ViolationStorage(useInMemory: true)
        }.value
        let violations = [
            Violation(ruleID: "rule_1", filePath: "File1.swift", line: 10, severity: .error, message: "Error")
        ]
        try await storage.storeViolations(violations, for: workspaceId)
        
        // Simulate app restart - create new manager with same UserDefaults
        let (recentCount, firstPath, workspace2) = try await MainActor.run {
            let manager2 = WorkspaceManager(userDefaults: defaultsCapture)
            // Recent workspaces should be persisted
            let recentCount = manager2.recentWorkspaces.count
            let firstPath = manager2.recentWorkspaces.first?.path
            
            // Re-open workspace
            try manager2.openWorkspace(at: tempDir)
            let workspace2 = try #require(manager2.currentWorkspace)
            
            return (recentCount, firstPath, workspace2)
        }
        
        #expect(recentCount == 1)
        #expect(firstPath == tempDir)
        
        // Workspace should have same path (ID might differ, but path is key)
        // Extract path inside MainActor context
        let workspace2Path = await MainActor.run {
            workspace2.path
        }
        #expect(workspace2Path == tempDir)
        
        // Violations should still be accessible
        let filter = ViolationFilter()
        let stored = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)
        #expect(stored.count == 1)
    }
    
    // MARK: - Error Handling Integration Tests
    
    @Test("Handles workspace deletion gracefully")
    func testHandlesWorkspaceDeletion() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        
        let (hasWorkspace, recentCount) = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return (manager.currentWorkspace != nil, manager.recentWorkspaces.count)
        }
        
        #expect(hasWorkspace == true)
        #expect(recentCount == 1)
        
        // Delete workspace directory
        WorkspaceTestHelpers.cleanupWorkspace(tempDir)
        
        // Create new manager - should filter out deleted workspace
        let isEmpty = try await withWorkspaceManager { newManager in
            return newManager.recentWorkspaces.isEmpty
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
            
            // Delete one workspace
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
