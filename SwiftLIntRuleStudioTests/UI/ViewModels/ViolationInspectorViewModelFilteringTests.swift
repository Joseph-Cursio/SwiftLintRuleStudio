import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct VIViewModelFilteringTests {
    @Test("ViolationInspectorViewModel filters by search text")
    func testFilterBySearchText() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(
                ruleID: "force_cast",
                message: "Force cast violation"
            ),
            ViolationInspectorViewModelTestHelpers.createTestViolation(
                ruleID: "line_length",
                message: "Line too long"
            )
        ]

        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId)
            viewModel.searchText = "force"
        }.value

        let (filteredCount, ruleID) = await MainActor.run {
            (viewModel.filteredViolations.count, viewModel.filteredViolations.first?.ruleID)
        }
        #expect(filteredCount == 1)
        #expect(ruleID == "force_cast")
    }

    @Test("ViolationInspectorViewModel filters by rule ID")
    func testFilterByRuleID() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule3")
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
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1", severity: .error),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2", severity: .warning),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule3", severity: .error)
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
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violation1 = ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1", suppressed: false)
        let violation2 = ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2", suppressed: true)

        try await mockStorage.storeViolations([violation1, violation2], for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        await MainActor.run {
            viewModel.showSuppressedOnly = true
        }

        let (filteredCount, isSuppressed) = await MainActor.run {
            (viewModel.filteredViolations.count, viewModel.filteredViolations.first?.suppressed == true)
        }
        #expect(filteredCount == 1)
        #expect(isSuppressed == true)
    }

    @Test("ViolationInspectorViewModel clears filters")
    func testClearFilters() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [ViolationInspectorViewModelTestHelpers.createTestViolation()]

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

        let cleared = await MainActor.run {
            (
                searchTextEmpty: viewModel.searchText.isEmpty,
                ruleIDsEmpty: viewModel.selectedRuleIDs.isEmpty,
                severitiesEmpty: viewModel.selectedSeverities.isEmpty
            )
        }
        #expect(cleared.searchTextEmpty == true)
        #expect(cleared.ruleIDsEmpty == true)
        #expect(cleared.severitiesEmpty == true)
    }
}
