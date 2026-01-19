//
//  ViolationInspectorViewModelTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for Violation Inspector ViewModel
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// ViolationInspectorViewModel is @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
struct ViolationInspectorViewModelTests {
    
    // MARK: - Test Helpers
    
    // Helper to create ViolationInspectorViewModel on MainActor
    private func createViolationInspectorViewModel(
        violationStorage: ViolationStorageProtocol,
        workspaceAnalyzer: WorkspaceAnalyzer? = nil
    ) async -> ViolationInspectorViewModel {
        // Capture with nonisolated(unsafe) to bypass Sendable check for test mocks
        nonisolated(unsafe) let storageCapture = violationStorage
        nonisolated(unsafe) let analyzerCapture = workspaceAnalyzer
        return await MainActor.run {
            ViolationInspectorViewModel(violationStorage: storageCapture, workspaceAnalyzer: analyzerCapture)
        }
    }
    
    private func createMockViolationStorage() -> MockViolationStorageForViewModel {
        return MockViolationStorageForViewModel()
    }
    
    private func createTestViolation(
        id: UUID = UUID(),
        ruleID: String = "test_rule",
        filePath: String = "Test.swift",
        line: Int = 10,
        severity: Severity = .warning,
        message: String = "Test violation",
        detectedAt: Date = Date(),
        suppressed: Bool = false
    ) -> Violation {
        return Violation(
            id: id,
            ruleID: ruleID,
            filePath: filePath,
            line: line,
            severity: severity,
            message: message,
            detectedAt: detectedAt,
            suppressed: suppressed
        )
    }
    
    // MARK: - Initialization Tests
    
    @Test("ViolationInspectorViewModel initializes with empty violations")
    func testInitialization() async {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let isEmpty = await MainActor.run {
            viewModel.violations.isEmpty
        }
        let (filteredEmpty, violationCount) = await MainActor.run {
            return (viewModel.filteredViolations.isEmpty, viewModel.violationCount)
        }
        #expect(isEmpty == true)
        #expect(filteredEmpty == true)
        #expect(violationCount == 0)
    }
    
    // MARK: - Loading Tests
    
    @Test("ViolationInspectorViewModel loads violations from storage")
    func testLoadViolations() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(ruleID: "rule1"),
            createTestViolation(ruleID: "rule2")
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId)
        }.value
        
        let (violationsCount, filteredCount, violationCount) = await MainActor.run {
            return (viewModel.violations.count, viewModel.filteredViolations.count, viewModel.violationCount)
        }
        #expect(violationsCount == 2)
        #expect(filteredCount == 2)
        #expect(violationCount == 2)
    }
    
    @Test("ViolationInspectorViewModel refreshes violations without analyzer (fallback)")
    func testRefreshViolationsWithoutAnalyzer() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [createTestViolation()]
        
        nonisolated(unsafe) let mockStorageCapture = mockStorage
        try await mockStorageCapture.storeViolations(violations, for: workspaceId)
        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId)
        }.value
        
        // Add more violations
        let newViolations = [createTestViolation(ruleID: "rule2")]
        try await mockStorage.storeViolations(newViolations, for: workspaceId)
        try await Task { @MainActor in
            try await viewModel.refreshViolations()
        }.value
        
        let violationsCount = await MainActor.run {
            viewModel.violations.count
        }
        #expect(violationsCount >= 1)
    }
    
    @Test("ViolationInspectorViewModel refreshes violations with analyzer")
    func testRefreshViolationsWithAnalyzer() async throws {
        let mockStorage = createMockViolationStorage()
        // MockWorkspaceAnalyzer is @MainActor, create it on MainActor
        nonisolated(unsafe) let mockStorageCapture = mockStorage
        let mockAnalyzer = await MainActor.run {
            MockWorkspaceAnalyzer(mockStorage: mockStorageCapture)
        }
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage, workspaceAnalyzer: mockAnalyzer)
        
        let workspaceId = UUID()
        // Workspace.init should be Sendable, but Swift 6 has false positive
        let workspace = await MainActor.run {
            // Use temporary directory instead of hard-coded path for portability
            let tempPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            return Workspace(path: tempPath)
        }
        
        // Initial violations
        let violations = [createTestViolation(ruleID: "rule1")]
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId, workspace: workspace)
        }.value
        
        let initialCallCount = await MainActor.run {
            mockAnalyzer.analyzeCallCount
        }
        
        // Setup analyzer to return new violations
        let newViolations = [createTestViolation(ruleID: "rule2"), createTestViolation(ruleID: "rule3")]
        await MainActor.run {
            mockAnalyzer.mockViolations = newViolations
        }
        
        // Refresh should trigger analysis (and loadViolations will also call analyze)
        try await Task { @MainActor in
            try await viewModel.refreshViolations()
        }.value
        
        // Should have loaded violations from storage (which includes the new ones from analysis)
        let (violationsCount, analyzeCallCount) = await MainActor.run {
            return (viewModel.violations.count, mockAnalyzer.analyzeCallCount)
        }
        #expect(violationsCount >= 1)
        // refreshViolations calls analyze, then loadViolations also calls analyze
        #expect(analyzeCallCount > initialCallCount)
    }
    
    @Test("ViolationInspectorViewModel loads violations with automatic analysis")
    func testLoadViolationsWithAutomaticAnalysis() async throws {
        let mockStorage = createMockViolationStorage()
        // MockWorkspaceAnalyzer is @MainActor, create it on MainActor
        nonisolated(unsafe) let mockStorageCapture = mockStorage
        let mockAnalyzer = await MainActor.run {
            MockWorkspaceAnalyzer(mockStorage: mockStorageCapture)
        }
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage, workspaceAnalyzer: mockAnalyzer)
        
        let workspaceId = UUID()
        // Workspace.init should be Sendable, but Swift 6 has false positive
        let workspace = await MainActor.run {
            // Use temporary directory instead of hard-coded path for portability
            let tempPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            return Workspace(path: tempPath)
        }
        
        // Setup analyzer to return violations
        let violations = [
            createTestViolation(ruleID: "rule1"),
            createTestViolation(ruleID: "rule2")
        ]
        await MainActor.run {
            mockAnalyzer.mockViolations = violations
        }
        
        // Load should trigger analysis automatically
        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId, workspace: workspace)
        }.value
        
        let (analyzeCallCount, violationsCount) = await MainActor.run {
            return (mockAnalyzer.analyzeCallCount, viewModel.violations.count)
        }
        #expect(analyzeCallCount == 1)
        #expect(violationsCount == 2)
    }
    
    @Test("ViolationInspectorViewModel handles analysis failure gracefully")
    func testLoadViolationsHandlesAnalysisFailure() async throws {
        let mockStorage = createMockViolationStorage()
        // MockWorkspaceAnalyzer is @MainActor, create it on MainActor
        nonisolated(unsafe) let mockStorageCapture = mockStorage
        let mockAnalyzer = await MainActor.run {
            MockWorkspaceAnalyzer(mockStorage: mockStorageCapture)
        }
        await MainActor.run {
            mockAnalyzer.shouldFail = true
        }
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage, workspaceAnalyzer: mockAnalyzer)
        
        let workspaceId = UUID()
        // Workspace.init should be Sendable, but Swift 6 has false positive
        let workspace = await MainActor.run {
            // Use temporary directory instead of hard-coded path for portability
            let tempPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            return Workspace(path: tempPath)
        }
        
        // Pre-store some violations
        let existingViolations = [createTestViolation(ruleID: "existing")]
        try await mockStorage.storeViolations(existingViolations, for: workspaceId)
        
        // Load should still work even if analysis fails
        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId, workspace: workspace)
        }.value
        
        // Should still load existing violations
        let (violationsCount, ruleID) = await MainActor.run {
            return (viewModel.violations.count, viewModel.violations.first?.ruleID)
        }
        #expect(violationsCount == 1)
        #expect(ruleID == "existing")
    }
    
    // MARK: - Filtering Tests
    
    @Test("ViolationInspectorViewModel filters by search text")
    func testFilterBySearchText() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(ruleID: "force_cast", message: "Force cast violation"),
            createTestViolation(ruleID: "line_length", message: "Line too long")
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId)
            viewModel.searchText = "force"
        }.value
        
        let (filteredCount, ruleID) = await MainActor.run {
            return (viewModel.filteredViolations.count, viewModel.filteredViolations.first?.ruleID)
        }
        #expect(filteredCount == 1)
        #expect(ruleID == "force_cast")
    }
    
    @Test("ViolationInspectorViewModel filters by rule ID")
    func testFilterByRuleID() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(ruleID: "rule1"),
            createTestViolation(ruleID: "rule2"),
            createTestViolation(ruleID: "rule3")
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId)
            viewModel.selectedRuleIDs = ["rule1", "rule3"]
        }.value
        
        let (filteredCount, allMatch) = await MainActor.run {
            let count = viewModel.filteredViolations.count
            let allMatch = viewModel.filteredViolations.allSatisfy { $0.ruleID == "rule1" || $0.ruleID == "rule3" }
            return (count, allMatch)
        }
        #expect(filteredCount == 2)
        #expect(allMatch == true)
    }
    
    @Test("ViolationInspectorViewModel filters by severity")
    func testFilterBySeverity() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(ruleID: "rule1", severity: .error),
            createTestViolation(ruleID: "rule2", severity: .warning),
            createTestViolation(ruleID: "rule3", severity: .error)
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId)
            viewModel.selectedSeverities = [.error]
        }.value
        
        let (filteredCount, allMatch) = await MainActor.run {
            let count = viewModel.filteredViolations.count
            let allMatch = viewModel.filteredViolations.allSatisfy { $0.severity == .error }
            return (count, allMatch)
        }
        #expect(filteredCount == 2)
        #expect(allMatch == true)
    }
    
    @Test("ViolationInspectorViewModel filters by file path")
    func testFilterByFilePath() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(ruleID: "rule1", filePath: "File1.swift"),
            createTestViolation(ruleID: "rule2", filePath: "File2.swift"),
            createTestViolation(ruleID: "rule3", filePath: "File1.swift")
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId)
            viewModel.selectedFiles = ["File1.swift"]
        }.value
        
        let (filteredCount, allMatch) = await MainActor.run {
            let count = viewModel.filteredViolations.count
            let allMatch = viewModel.filteredViolations.allSatisfy { $0.filePath == "File1.swift" }
            return (count, allMatch)
        }
        #expect(filteredCount == 2)
        #expect(allMatch == true)
    }
    
    @Test("ViolationInspectorViewModel filters suppressed violations")
    func testFilterSuppressedViolations() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violation1 = createTestViolation(ruleID: "rule1", suppressed: false)
        let violation2 = createTestViolation(ruleID: "rule2", suppressed: true)
        
        try await mockStorage.storeViolations([violation1, violation2], for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        await MainActor.run {
            viewModel.showSuppressedOnly = true
        }
        
        let (filteredCount, isSuppressed) = await MainActor.run {
            return (viewModel.filteredViolations.count, viewModel.filteredViolations.first?.suppressed == true)
        }
        #expect(filteredCount == 1)
        #expect(isSuppressed == true)
    }
    
    @Test("ViolationInspectorViewModel clears filters")
    func testClearFilters() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [createTestViolation()]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        await MainActor.run {
            viewModel.searchText = "test"
            viewModel.selectedRuleIDs = ["rule1"]
            viewModel.selectedSeverities = [.error]
        }
        
        await MainActor.run {
            viewModel.clearFilters()
        }
        
        let (searchTextEmpty, ruleIDsEmpty, severitiesEmpty) = await MainActor.run {
            return (viewModel.searchText.isEmpty, viewModel.selectedRuleIDs.isEmpty, viewModel.selectedSeverities.isEmpty)
        }
        #expect(searchTextEmpty == true)
        #expect(ruleIDsEmpty == true)
        #expect(severitiesEmpty == true)
    }
    
    // MARK: - Sorting Tests
    
    @Test("ViolationInspectorViewModel sorts by file")
    func testSortByFile() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(ruleID: "rule1", filePath: "FileB.swift", line: 10),
            createTestViolation(ruleID: "rule2", filePath: "FileA.swift", line: 5),
            createTestViolation(ruleID: "rule3", filePath: "FileC.swift", line: 15)
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        await MainActor.run {
            viewModel.sortOption = .file
        }
        
        let (count, filePath0, filePath1, filePath2) = await MainActor.run {
            return (
                viewModel.filteredViolations.count,
                viewModel.filteredViolations[0].filePath,
                viewModel.filteredViolations[1].filePath,
                viewModel.filteredViolations[2].filePath
            )
        }
        #expect(count == 3)
        #expect(filePath0 == "FileA.swift")
        #expect(filePath1 == "FileB.swift")
        #expect(filePath2 == "FileC.swift")
    }
    
    @Test("ViolationInspectorViewModel sorts by line number")
    func testSortByLine() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(ruleID: "rule1", filePath: "Test.swift", line: 30),
            createTestViolation(ruleID: "rule2", filePath: "Test.swift", line: 10),
            createTestViolation(ruleID: "rule3", filePath: "Test.swift", line: 20)
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        await MainActor.run {
            viewModel.sortOption = .line
        }
        
        let (count, line0, line1, line2) = await MainActor.run {
            return (
                viewModel.filteredViolations.count,
                viewModel.filteredViolations[0].line,
                viewModel.filteredViolations[1].line,
                viewModel.filteredViolations[2].line
            )
        }
        #expect(count == 3)
        #expect(line0 == 10)
        #expect(line1 == 20)
        #expect(line2 == 30)
    }
    
    @Test("ViolationInspectorViewModel sorts by severity")
    func testSortBySeverity() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(ruleID: "rule1", severity: .warning),
            createTestViolation(ruleID: "rule2", severity: .error),
            createTestViolation(ruleID: "rule3", severity: .warning)
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        await MainActor.run {
            viewModel.sortOption = .severity
        }
        
        let (count, severity0) = await MainActor.run {
            return (viewModel.filteredViolations.count, viewModel.filteredViolations[0].severity)
        }
        #expect(count == 3)
        #expect(severity0 == .error)
    }
    
    @Test("ViolationInspectorViewModel sorts by date")
    func testSortByDate() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let oldDate = Date().addingTimeInterval(-86400)
        let newDate = Date()
        
        let violations = [
            createTestViolation(ruleID: "rule1", detectedAt: oldDate),
            createTestViolation(ruleID: "rule2", detectedAt: newDate),
            createTestViolation(ruleID: "rule3", detectedAt: oldDate)
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        await MainActor.run {
            viewModel.sortOption = .date
        }
        
        let (count, ruleID0) = await MainActor.run {
            return (viewModel.filteredViolations.count, viewModel.filteredViolations[0].ruleID)
        }
        #expect(count == 3)
        // Most recent first
        #expect(ruleID0 == "rule2")
    }
    
    // MARK: - Statistics Tests
    
    @Test("ViolationInspectorViewModel calculates statistics")
    func testStatistics() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(ruleID: "rule1", severity: .error),
            createTestViolation(ruleID: "rule2", severity: .error),
            createTestViolation(ruleID: "rule3", severity: .warning),
            createTestViolation(ruleID: "rule4", severity: .warning)
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        let (violationCount, errorCount, warningCount) = await MainActor.run {
            return (viewModel.violationCount, viewModel.errorCount, viewModel.warningCount)
        }
        #expect(violationCount == 4)
        #expect(errorCount == 2)
        #expect(warningCount == 2)
    }
    
    @Test("ViolationInspectorViewModel extracts unique rules")
    func testUniqueRules() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(ruleID: "rule1"),
            createTestViolation(ruleID: "rule2"),
            createTestViolation(ruleID: "rule1"), // Duplicate
            createTestViolation(ruleID: "rule3")
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        let uniqueRules = await MainActor.run {
            viewModel.uniqueRules
        }
        #expect(uniqueRules.count == 3)
        #expect(uniqueRules.contains("rule1"))
        #expect(uniqueRules.contains("rule2"))
        #expect(uniqueRules.contains("rule3"))
    }
    
    @Test("ViolationInspectorViewModel extracts unique files")
    func testUniqueFiles() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(ruleID: "rule1", filePath: "File1.swift"),
            createTestViolation(ruleID: "rule2", filePath: "File2.swift"),
            createTestViolation(ruleID: "rule3", filePath: "File1.swift") // Duplicate
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        let uniqueFiles = await MainActor.run {
            viewModel.uniqueFiles
        }
        #expect(uniqueFiles.count == 2)
        #expect(uniqueFiles.contains("File1.swift"))
        #expect(uniqueFiles.contains("File2.swift"))
    }
    
    // MARK: - Selection Tests
    
    @Test("ViolationInspectorViewModel selects next violation")
    func testSelectNextViolation() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(id: UUID(), ruleID: "rule1"),
            createTestViolation(id: UUID(), ruleID: "rule2"),
            createTestViolation(id: UUID(), ruleID: "rule3")
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        let (violation0Id, violation1Id) = await MainActor.run {
            return (violations[0].id, violations[1].id)
        }
        await MainActor.run {
            viewModel.selectedViolationId = violation0Id
        }
        await MainActor.run {
            viewModel.selectNextViolation()
        }
        
        let selectedId = await MainActor.run {
            viewModel.selectedViolationId
        }
        #expect(selectedId == violation1Id)
    }
    
    @Test("ViolationInspectorViewModel selects previous violation")
    func testSelectPreviousViolation() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(id: UUID(), ruleID: "rule1"),
            createTestViolation(id: UUID(), ruleID: "rule2"),
            createTestViolation(id: UUID(), ruleID: "rule3")
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        let (violation0Id, violation1Id) = await MainActor.run {
            return (violations[0].id, violations[1].id)
        }
        await MainActor.run {
            viewModel.selectedViolationId = violation1Id
        }
        await MainActor.run {
            viewModel.selectPreviousViolation()
        }
        
        let selectedId = await MainActor.run {
            viewModel.selectedViolationId
        }
        #expect(selectedId == violation0Id)
    }
    
    @Test("ViolationInspectorViewModel selects all violations")
    func testSelectAll() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(id: UUID(), ruleID: "rule1"),
            createTestViolation(id: UUID(), ruleID: "rule2")
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        let (violation0Id, violation1Id) = await MainActor.run {
            return (violations[0].id, violations[1].id)
        }
        await MainActor.run {
            viewModel.selectAll()
        }
        
        let (selectedCount, contains0, contains1) = await MainActor.run {
            return (
                viewModel.selectedViolationIds.count,
                viewModel.selectedViolationIds.contains(violation0Id),
                viewModel.selectedViolationIds.contains(violation1Id)
            )
        }
        #expect(selectedCount == 2)
        #expect(contains0 == true)
        #expect(contains1 == true)
    }
    
    @Test("ViolationInspectorViewModel deselects all violations")
    func testDeselectAll() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [createTestViolation()]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        await MainActor.run {
            viewModel.selectAll()
        }
        let selectedCount1 = await MainActor.run {
            viewModel.selectedViolationIds.count
        }
        #expect(selectedCount1 == 1)
        
        await MainActor.run {
            viewModel.deselectAll()
        }
        let isEmpty = await MainActor.run {
            viewModel.selectedViolationIds.isEmpty
        }
        #expect(isEmpty == true)
    }
    
    // MARK: - Bulk Operations Tests
    
    @Test("ViolationInspectorViewModel suppresses selected violations")
    func testSuppressSelectedViolations() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violation1 = createTestViolation(id: UUID(), ruleID: "rule1")
        let violation2 = createTestViolation(id: UUID(), ruleID: "rule2")
        
        try await mockStorage.storeViolations([violation1, violation2], for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        let (violation1Id, violation2Id) = await MainActor.run {
            return (violation1.id, violation2.id)
        }
        await MainActor.run {
            viewModel.selectedViolationIds = [violation1Id, violation2Id]
        }
        try await viewModel.suppressSelectedViolations(reason: "Test suppression")
        
        // Refresh to get updated violations
        try await Task { @MainActor in
            try await viewModel.refreshViolations()
        }.value
        
        let (suppressedCount, selectedIdsEmpty) = await MainActor.run {
            let suppressed = viewModel.violations.filter { $0.suppressed }
            return (suppressed.count, viewModel.selectedViolationIds.isEmpty)
        }
        #expect(suppressedCount == 2)
        #expect(selectedIdsEmpty == true) // Should clear selection
    }
    
    @Test("ViolationInspectorViewModel resolves selected violations")
    func testResolveSelectedViolations() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violation1 = createTestViolation(id: UUID(), ruleID: "rule1")
        let violation2 = createTestViolation(id: UUID(), ruleID: "rule2")
        
        try await mockStorage.storeViolations([violation1, violation2], for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        let (violation1Id, violation2Id) = await MainActor.run {
            return (violation1.id, violation2.id)
        }
        await MainActor.run {
            viewModel.selectedViolationIds = [violation1Id, violation2Id]
        }
        try await viewModel.resolveSelectedViolations()
        
        // Refresh to get updated violations
        try await Task { @MainActor in
            try await viewModel.refreshViolations()
        }.value
        
        let (resolvedCount, selectedIdsEmpty) = await MainActor.run {
            let resolved = viewModel.violations.filter { $0.resolvedAt != nil }
            return (resolved.count, viewModel.selectedViolationIds.isEmpty)
        }
        #expect(resolvedCount == 2)
        #expect(selectedIdsEmpty == true) // Should clear selection
    }
    
    // MARK: - Edge Cases
    
    @Test("ViolationInspectorViewModel handles empty violation list")
    func testEmptyViolationList() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        try await viewModel.loadViolations(for: workspaceId)
        
        let (violationsEmpty, filteredEmpty, violationCount, errorCount, warningCount) = await MainActor.run {
            return (
                viewModel.violations.isEmpty,
                viewModel.filteredViolations.isEmpty,
                viewModel.violationCount,
                viewModel.errorCount,
                viewModel.warningCount
            )
        }
        #expect(violationsEmpty == true)
        #expect(filteredEmpty == true)
        #expect(violationCount == 0)
        #expect(errorCount == 0)
        #expect(warningCount == 0)
    }
    
    @Test("ViolationInspectorViewModel handles next violation at end of list")
    func testSelectNextAtEnd() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(id: UUID(), ruleID: "rule1"),
            createTestViolation(id: UUID(), ruleID: "rule2")
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        let violation1Id = await MainActor.run {
            violations[1].id
        }
        await MainActor.run {
            viewModel.selectedViolationId = violation1Id
        }
        let previousId = await MainActor.run {
            viewModel.selectedViolationId
        }
        await MainActor.run {
            viewModel.selectNextViolation()
        }
        
        // Should not change (already at end)
        let currentId = await MainActor.run {
            viewModel.selectedViolationId
        }
        #expect(currentId == previousId)
    }
    
    @Test("ViolationInspectorViewModel handles previous violation at start of list")
    func testSelectPreviousAtStart() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(id: UUID(), ruleID: "rule1"),
            createTestViolation(id: UUID(), ruleID: "rule2")
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        let violation0Id = await MainActor.run {
            violations[0].id
        }
        await MainActor.run {
            viewModel.selectedViolationId = violation0Id
        }
        let previousId = await MainActor.run {
            viewModel.selectedViolationId
        }
        await MainActor.run {
            viewModel.selectPreviousViolation()
        }
        
        // Should not change (already at start)
        let currentId = await MainActor.run {
            viewModel.selectedViolationId
        }
        #expect(currentId == previousId)
    }
    
    @Test("ViolationInspectorViewModel combines multiple filters")
    func testCombinedFilters() async throws {
        let mockStorage = createMockViolationStorage()
        let viewModel = await createViolationInspectorViewModel(violationStorage: mockStorage)
        
        let workspaceId = UUID()
        let violations = [
            createTestViolation(ruleID: "rule1", filePath: "File1.swift", severity: .error),
            createTestViolation(ruleID: "rule2", filePath: "File2.swift", severity: .error),
            createTestViolation(ruleID: "rule1", filePath: "File1.swift", severity: .warning),
            createTestViolation(ruleID: "rule3", filePath: "File3.swift", severity: .error)
        ]
        
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        
        await MainActor.run {
            viewModel.selectedRuleIDs = ["rule1"]
            viewModel.selectedSeverities = [.error]
            viewModel.selectedFiles = ["File1.swift"]
        }
        
        // Should only match rule1, error severity, in File1.swift
        let (filteredCount, ruleID, severity, filePath) = await MainActor.run {
            return (
                viewModel.filteredViolations.count,
                viewModel.filteredViolations.first?.ruleID,
                viewModel.filteredViolations.first?.severity,
                viewModel.filteredViolations.first?.filePath
            )
        }
        #expect(filteredCount == 1)
        #expect(ruleID == "rule1")
        #expect(severity == .error)
        #expect(filePath == "File1.swift")
    }
}

// MARK: - Mock Implementation

@MainActor
class MockWorkspaceAnalyzer: WorkspaceAnalyzer {
    var mockViolations: [Violation] = []
    var analyzeCallCount = 0
    var shouldFail = false
    private let mockStorage: MockViolationStorageForViewModel
    
    init(mockStorage: MockViolationStorageForViewModel) {
        self.mockStorage = mockStorage
        // Create a minimal mock CLI and storage for the parent initializer
        let mockCLI = MockSwiftLintCLI()
        super.init(swiftLintCLI: mockCLI, violationStorage: mockStorage)
    }
    
    override func analyze(workspace: Workspace, configPath: URL? = nil, scope: AnalysisScope? = nil) async throws -> AnalysisResult {
        analyzeCallCount += 1
        
        if shouldFail {
            throw WorkspaceAnalyzerError.analysisFailed("Mock analysis failure")
        }
        
        // Store violations in the storage
        try await mockStorage.storeViolations(mockViolations, for: workspace.id)
        
        return AnalysisResult(
            violations: mockViolations,
            filesAnalyzed: Set(mockViolations.map { $0.filePath }).count,
            duration: 0.1,
            startedAt: Date(),
            completedAt: Date()
        )
    }
}

class MockViolationStorageForViewModel: ViolationStorageProtocol {
    var storedViolations: [Violation] = []
    var storedWorkspaceIds: [UUID] = []
    
    func storeViolations(_ violations: [Violation], for workspaceId: UUID) throws {
        storedViolations.append(contentsOf: violations)
        storedWorkspaceIds.append(workspaceId)
    }
    
    func fetchViolations(filter: ViolationFilter, workspaceId: UUID?) throws -> [Violation] {
        var filtered = storedViolations
        
        if let workspaceId = workspaceId {
            // In real implementation, filter by workspace
            // For mock, we'll just return all
        }
        
        if let ruleIDs = filter.ruleIDs {
            filtered = filtered.filter { ruleIDs.contains($0.ruleID) }
        }
        
        if let severities = filter.severities {
            filtered = filtered.filter { severities.contains($0.severity) }
        }
        
        if let suppressedOnly = filter.suppressedOnly {
            filtered = filtered.filter { $0.suppressed == suppressedOnly }
        }
        
        if let filePaths = filter.filePaths {
            filtered = filtered.filter { filePaths.contains($0.filePath) }
        }
        
        return filtered
    }
    
    func suppressViolations(_ violationIds: [UUID], reason: String) throws {
        for (index, violation) in storedViolations.enumerated() where violationIds.contains(violation.id) {
            storedViolations[index] = Violation(
                id: violation.id,
                ruleID: violation.ruleID,
                filePath: violation.filePath,
                line: violation.line,
                column: violation.column,
                severity: violation.severity,
                message: violation.message,
                detectedAt: violation.detectedAt,
                resolvedAt: violation.resolvedAt,
                suppressed: true,
                suppressionReason: reason
            )
        }
    }
    
    func resolveViolations(_ violationIds: [UUID]) throws {
        for (index, violation) in storedViolations.enumerated() where violationIds.contains(violation.id) {
            storedViolations[index] = Violation(
                id: violation.id,
                ruleID: violation.ruleID,
                filePath: violation.filePath,
                line: violation.line,
                column: violation.column,
                severity: violation.severity,
                message: violation.message,
                detectedAt: violation.detectedAt,
                resolvedAt: Date(),
                suppressed: violation.suppressed,
                suppressionReason: violation.suppressionReason
            )
        }
    }
    
    func deleteViolations(for workspaceId: UUID) throws {
        storedViolations.removeAll()
    }
    
    func getViolationCount(filter: ViolationFilter, workspaceId: UUID?) async throws -> Int {
        let violations = try await fetchViolations(filter: filter, workspaceId: workspaceId)
        return violations.count
    }
}

