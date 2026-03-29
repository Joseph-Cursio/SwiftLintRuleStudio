import Foundation
import Testing
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

@Suite("ViolationInspectorViewModel Filtering", .tags(.viewModel))
@MainActor
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

        let filteredCount = await MainActor.run { viewModel.filteredViolations.count }
        #expect(filteredCount == 1)
        let first = try #require(await MainActor.run { viewModel.filteredViolations.first })
        #expect(first.ruleID == "force_cast")
    }

    // Individual filter tests (expanded from parameterized test to avoid
    // @Test(arguments:) macro conflict with MainActor-isolated static properties)

    @Test("ViolationInspectorViewModel filters violations by rule ID", .tags(.filtering))
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
            (viewModel.filteredViolations.count,
             viewModel.filteredViolations.allSatisfy { $0.ruleID == "rule1" || $0.ruleID == "rule3" })
        }
        #expect(filteredCount == 2)
        #expect(allMatch)
    }

    @Test("ViolationInspectorViewModel filters violations by severity", .tags(.filtering))
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
            (viewModel.filteredViolations.count,
             viewModel.filteredViolations.allSatisfy { $0.severity == .error })
        }
        #expect(filteredCount == 2)
        #expect(allMatch)
    }

    @Test("ViolationInspectorViewModel filters violations by file path", .tags(.filtering))
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
            (viewModel.filteredViolations.count,
             viewModel.filteredViolations.allSatisfy { $0.filePath == "File1.swift" })
        }
        #expect(filteredCount == 2)
        #expect(allMatch)
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

        let filteredCount = await MainActor.run { viewModel.filteredViolations.count }
        #expect(filteredCount == 1)
        let first = try #require(await MainActor.run { viewModel.filteredViolations.first })
        #expect(first.suppressed)
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
        #expect(cleared.searchTextEmpty)
        #expect(cleared.ruleIDsEmpty)
        #expect(cleared.severitiesEmpty)
    }
}
