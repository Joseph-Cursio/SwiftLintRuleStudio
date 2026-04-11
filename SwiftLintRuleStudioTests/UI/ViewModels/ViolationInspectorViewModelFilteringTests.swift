import Foundation
import Testing
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

// Defined at file level to avoid @Test(arguments:) conflict with @MainActor-isolated static properties
enum ViewModelFilterCase: CaseIterable, Sendable, CustomTestStringConvertible {
    case byRuleID, bySeverity, byFilePath

    var testDescription: String {
        switch self {
        case .byRuleID: "rule ID"
        case .bySeverity: "severity"
        case .byFilePath: "file path"
        }
    }

    var violations: [Violation] {
        switch self {
        case .byRuleID: [
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule3")
        ]
        case .bySeverity: [
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1", severity: .error),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2", severity: .warning),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule3", severity: .error)
        ]
        case .byFilePath: [
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1", filePath: "File1.swift"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2", filePath: "File2.swift"),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule3", filePath: "File1.swift")
        ]
        }
    }

    @MainActor
    func applyFilter(to viewModel: ViolationInspectorViewModel) {
        switch self {
        case .byRuleID: viewModel.selectedRuleIDs = ["rule1", "rule3"]
        case .bySeverity: viewModel.selectedSeverities = [.error]
        case .byFilePath: viewModel.selectedFiles = ["File1.swift"]
        }
    }

    func allMatch(_ fetched: [Violation]) -> Bool {
        switch self {
        case .byRuleID: fetched.allSatisfy { $0.ruleID == "rule1" || $0.ruleID == "rule3" }
        case .bySeverity: fetched.allSatisfy { $0.severity == .error }
        case .byFilePath: fetched.allSatisfy { $0.filePath == "File1.swift" }
        }
    }
}

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
        try await viewModel.loadViolations(for: workspaceId)
        viewModel.searchText = "force"

        #expect(viewModel.filteredViolations.count == 1)
        let first = try #require(viewModel.filteredViolations.first)
        #expect(first.ruleID == "force_cast")
    }

    @Test("ViolationInspectorViewModel filters violations", .tags(.filtering),
          arguments: ViewModelFilterCase.allCases)
    func testFilter(_ filterCase: ViewModelFilterCase) async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )
        let workspaceId = UUID()

        try await mockStorage.storeViolations(filterCase.violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        filterCase.applyFilter(to: viewModel)

        #expect(viewModel.filteredViolations.count == 2)
        #expect(filterCase.allMatch(viewModel.filteredViolations))
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
        viewModel.showSuppressedOnly = true

        #expect(viewModel.filteredViolations.count == 1)
        let first = try #require(viewModel.filteredViolations.first)
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

        viewModel.searchText = "test"
        viewModel.selectedRuleIDs = ["rule1"]
        viewModel.selectedSeverities = [.error]

        viewModel.clearFilters()

        #expect(viewModel.searchText.isEmpty)
        #expect(viewModel.selectedRuleIDs.isEmpty)
        #expect(viewModel.selectedSeverities.isEmpty)
    }
}
