import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct VIViewModelStatsSelectionTests {
    @Test("ViolationInspectorViewModel calculates statistics")
    func testStatistics() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1", severity: .error),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2", severity: .error),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule3", severity: .warning),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule4", severity: .warning)
        ]

        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        let (violationCount, errorCount, warningCount) = await MainActor.run {
            (viewModel.violationCount, viewModel.errorCount, viewModel.warningCount)
        }
        #expect(violationCount == 4)
        #expect(errorCount == 2)
        #expect(warningCount == 2)
    }

    @Test("ViolationInspectorViewModel extracts unique rules")
    func testUniqueRules() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule3")
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
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1", filePath: "File1.swift"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2", filePath: "File2.swift"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule3", filePath: "File1.swift")
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

    @Test("ViolationInspectorViewModel selects next violation")
    func testSelectNextViolation() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(id: UUID(), ruleID: "rule1"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(id: UUID(), ruleID: "rule2"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(id: UUID(), ruleID: "rule3")
        ]

        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        let (violation0Id, violation1Id) = await MainActor.run {
            (violations[0].id, violations[1].id)
        }
        await MainActor.run {
            viewModel.selectedViolationId = violation0Id
            viewModel.selectNextViolation()
        }

        let selectedId = await MainActor.run {
            viewModel.selectedViolationId
        }
        #expect(selectedId == violation1Id)
    }

    @Test("ViolationInspectorViewModel selects previous violation")
    func testSelectPreviousViolation() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(id: UUID(), ruleID: "rule1"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(id: UUID(), ruleID: "rule2"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(id: UUID(), ruleID: "rule3")
        ]

        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        let (violation0Id, violation1Id) = await MainActor.run {
            (violations[0].id, violations[1].id)
        }
        await MainActor.run {
            viewModel.selectedViolationId = violation1Id
            viewModel.selectPreviousViolation()
        }

        let selectedId = await MainActor.run {
            viewModel.selectedViolationId
        }
        #expect(selectedId == violation0Id)
    }

    @Test("ViolationInspectorViewModel selects all violations")
    func testSelectAll() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(id: UUID(), ruleID: "rule1"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(id: UUID(), ruleID: "rule2")
        ]

        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        let (violation0Id, violation1Id) = await MainActor.run {
            (violations[0].id, violations[1].id)
        }
        await MainActor.run {
            viewModel.selectAll()
        }

        let (selectedCount, contains0, contains1) = await MainActor.run {
            (
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
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [ViolationInspectorViewModelTestHelpers.createTestViolation()]

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
}
