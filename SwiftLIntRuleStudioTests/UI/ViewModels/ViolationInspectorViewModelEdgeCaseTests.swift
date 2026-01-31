import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct VIViewModelEdgeCaseTests {
    @Test("ViolationInspectorViewModel handles empty violation list")
    func testEmptyViolationList() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        try await viewModel.loadViolations(for: workspaceId)

        let (violationsEmpty, filteredEmpty, violationCount, errorCount, warningCount) = await MainActor.run {
            (
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

        let currentId = await MainActor.run {
            viewModel.selectedViolationId
        }
        #expect(currentId == previousId)
    }

    @Test("ViolationInspectorViewModel selects first when next called without selection")
    func testSelectNextWithoutSelection() async throws {
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

        await MainActor.run {
            viewModel.selectedViolationId = nil
            viewModel.selectNextViolation()
        }

        let selectedId = await MainActor.run {
            viewModel.selectedViolationId
        }
        let expectedId = await MainActor.run {
            violations.first?.id
        }
        #expect(selectedId == expectedId)
    }

    @Test("ViolationInspectorViewModel handles previous violation at start of list")
    func testSelectPreviousAtStart() async throws {
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

        let currentId = await MainActor.run {
            viewModel.selectedViolationId
        }
        #expect(currentId == previousId)
    }

    @Test("ViolationInspectorViewModel selects last when previous called without selection")
    func testSelectPreviousWithoutSelection() async throws {
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

        await MainActor.run {
            viewModel.selectedViolationId = nil
            viewModel.selectPreviousViolation()
        }

        let selectedId = await MainActor.run {
            viewModel.selectedViolationId
        }
        let expectedId = await MainActor.run {
            violations.last?.id
        }
        #expect(selectedId == expectedId)
    }

    @Test("ViolationInspectorViewModel syncs selection from multi-select")
    func testSelectionSyncFromSet() async throws {
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

        let selectedId = await MainActor.run {
            violations[1].id
        }
        await MainActor.run {
            viewModel.selectedViolationIds = [selectedId]
        }

        let primaryId = await MainActor.run {
            viewModel.selectedViolationId
        }
        #expect(primaryId == selectedId)
    }

    @Test("ViolationInspectorViewModel combines multiple filters")
    func testCombinedFilters() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(
                ruleID: "rule1",
                filePath: "File1.swift",
                severity: .error
            ),
            ViolationInspectorViewModelTestHelpers.createTestViolation(
                ruleID: "rule2",
                filePath: "File2.swift",
                severity: .error
            ),
            ViolationInspectorViewModelTestHelpers.createTestViolation(
                ruleID: "rule1",
                filePath: "File1.swift",
                severity: .warning
            ),
            ViolationInspectorViewModelTestHelpers.createTestViolation(
                ruleID: "rule3",
                filePath: "File3.swift",
                severity: .error
            )
        ]

        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        await MainActor.run {
            viewModel.selectedRuleIDs = ["rule1"]
            viewModel.selectedSeverities = [.error]
            viewModel.selectedFiles = ["File1.swift"]
        }

        let (filteredCount, ruleID, severity, filePath) = await MainActor.run {
            (
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
