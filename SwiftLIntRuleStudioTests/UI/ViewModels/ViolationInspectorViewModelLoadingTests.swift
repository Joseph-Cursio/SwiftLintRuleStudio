import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// ViolationInspectorViewModel is @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
struct VIViewModelLoadingTests {
    @Test("ViolationInspectorViewModel initializes with empty violations")
    func testInitialization() async {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let isEmpty = await MainActor.run {
            viewModel.violations.isEmpty
        }
        let (filteredEmpty, violationCount) = await MainActor.run {
            (viewModel.filteredViolations.isEmpty, viewModel.violationCount)
        }
        #expect(isEmpty == true)
        #expect(filteredEmpty == true)
        #expect(violationCount == 0)
    }

    @Test("ViolationInspectorViewModel loads violations from storage")
    func testLoadViolations() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2")
        ]

        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId)
        }.value

        let (violationsCount, filteredCount, violationCount) = await MainActor.run {
            (viewModel.violations.count, viewModel.filteredViolations.count, viewModel.violationCount)
        }
        #expect(violationsCount == 2)
        #expect(filteredCount == 2)
        #expect(violationCount == 2)
    }

    @Test("ViolationInspectorViewModel refreshes violations without analyzer (fallback)")
    func testRefreshViolationsWithoutAnalyzer() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [ViolationInspectorViewModelTestHelpers.createTestViolation()]

        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId)
        }.value

        let newViolations = [ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2")]
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
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let mockAnalyzer = await MainActor.run {
            MockWorkspaceAnalyzer(mockStorage: mockStorage)
        }
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage,
            workspaceAnalyzer: mockAnalyzer
        )

        let workspaceId = UUID()
        let workspace = await MainActor.run {
            let tempPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            return Workspace(path: tempPath)
        }

        let violations = [ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1")]
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId, workspace: workspace)
        }.value

        let initialCallCount = await MainActor.run {
            mockAnalyzer.analyzeCallCount
        }

        let newViolations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule3")
        ]
        await MainActor.run {
            mockAnalyzer.mockViolations = newViolations
        }

        try await Task { @MainActor in
            try await viewModel.refreshViolations()
        }.value

        let (violationsCount, analyzeCallCount) = await MainActor.run {
            (viewModel.violations.count, mockAnalyzer.analyzeCallCount)
        }
        #expect(violationsCount >= 1)
        #expect(analyzeCallCount > initialCallCount)
    }

    @Test("ViolationInspectorViewModel loads violations with automatic analysis")
    func testLoadViolationsWithAutomaticAnalysis() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let mockAnalyzer = await MainActor.run {
            MockWorkspaceAnalyzer(mockStorage: mockStorage)
        }
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage,
            workspaceAnalyzer: mockAnalyzer
        )

        let workspaceId = UUID()
        let workspace = await MainActor.run {
            let tempPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            return Workspace(path: tempPath)
        }

        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2")
        ]
        await MainActor.run {
            mockAnalyzer.mockViolations = violations
        }

        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId, workspace: workspace)
        }.value

        let (analyzeCallCount, violationsCount) = await MainActor.run {
            (mockAnalyzer.analyzeCallCount, viewModel.violations.count)
        }
        #expect(analyzeCallCount == 1)
        #expect(violationsCount == 2)
    }

    @Test("ViolationInspectorViewModel handles analysis failure gracefully")
    func testLoadViolationsHandlesAnalysisFailure() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let mockAnalyzer = await MainActor.run {
            MockWorkspaceAnalyzer(mockStorage: mockStorage)
        }
        await MainActor.run {
            mockAnalyzer.shouldFail = true
        }
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage,
            workspaceAnalyzer: mockAnalyzer
        )

        let workspaceId = UUID()
        let workspace = await MainActor.run {
            let tempPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            return Workspace(path: tempPath)
        }

        let existingViolations = [ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "existing")]
        try await mockStorage.storeViolations(existingViolations, for: workspaceId)

        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId, workspace: workspace)
        }.value

        let (violationsCount, ruleID) = await MainActor.run {
            (viewModel.violations.count, viewModel.violations.first?.ruleID)
        }
        #expect(violationsCount == 1)
        #expect(ruleID == "existing")
    }
}
