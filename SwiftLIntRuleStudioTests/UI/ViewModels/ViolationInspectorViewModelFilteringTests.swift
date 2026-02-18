import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct VMFilterCase: Sendable, CustomTestStringConvertible {
    let name: String
    let violations: [Violation]
    let configure: @MainActor @Sendable (ViolationInspectorViewModel) -> Void
    let expectedCount: Int
    let predicate: @Sendable (Violation) -> Bool

    var testDescription: String { name }

    static let all: [VMFilterCase] = [
        VMFilterCase(
            name: "by rule ID",
            violations: [
                ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1"),
                ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2"),
                ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule3")
            ],
            configure: { viewModel in viewModel.selectedRuleIDs = ["rule1", "rule3"] },
            expectedCount: 2,
            predicate: { $0.ruleID == "rule1" || $0.ruleID == "rule3" }
        ),
        VMFilterCase(
            name: "by severity",
            violations: [
                ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1", severity: .error),
                ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2", severity: .warning),
                ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule3", severity: .error)
            ],
            configure: { viewModel in viewModel.selectedSeverities = [.error] },
            expectedCount: 2,
            predicate: { $0.severity == .error }
        ),
        VMFilterCase(
            name: "by file path",
            violations: [
                ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1", filePath: "File1.swift"),
                ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2", filePath: "File2.swift"),
                ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule3", filePath: "File1.swift")
            ],
            configure: { viewModel in viewModel.selectedFiles = ["File1.swift"] },
            expectedCount: 2,
            predicate: { $0.filePath == "File1.swift" }
        )
    ]
}

@Suite("ViolationInspectorViewModel Filtering", .tags(.viewModel))
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

    @Test("ViolationInspectorViewModel filters violations", .tags(.filtering), arguments: VMFilterCase.all)
    func testFilterViolations(_ filterCase: VMFilterCase) async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )
        let workspaceId = UUID()

        try await mockStorage.storeViolations(filterCase.violations, for: workspaceId)
        try await Task { @MainActor in
            try await viewModel.loadViolations(for: workspaceId)
            filterCase.configure(viewModel)
        }.value

        let (filteredCount, allMatch) = await MainActor.run {
            let count = viewModel.filteredViolations.count
            let allMatch = viewModel.filteredViolations.allSatisfy(filterCase.predicate)
            return (count, allMatch)
        }
        #expect(filteredCount == filterCase.expectedCount)
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

        let filteredCount = await MainActor.run { viewModel.filteredViolations.count }
        #expect(filteredCount == 1)
        let first = try #require(await MainActor.run { viewModel.filteredViolations.first })
        #expect(first.suppressed == true)
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
