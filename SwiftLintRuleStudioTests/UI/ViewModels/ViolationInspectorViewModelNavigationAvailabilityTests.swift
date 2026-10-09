import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

/// `canSelectPreviousViolation` / `canSelectNextViolation` drive whether the
/// toolbar's Previous and Next buttons are enabled, so they must agree with what
/// `selectPreviousViolation()` / `selectNextViolation()` actually do.
@MainActor
struct ViolationInspectorViewModelNavigationAvailabilityTests {
    private func makeViewModel(violationCount: Int) async throws -> ViolationInspectorViewModel {
        let storage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: storage
        )
        let workspaceId = UUID()
        let violations = (0..<violationCount).map { index in
            ViolationInspectorViewModelTestHelpers.createTestViolation(id: UUID(), ruleID: "rule\(index)")
        }
        try await storage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)
        return viewModel
    }

    @Test("Nothing to navigate when there are no violations")
    func testEmptyList() async throws {
        let viewModel = try await makeViewModel(violationCount: 0)
        #expect(!viewModel.canSelectPreviousViolation)
        #expect(!viewModel.canSelectNextViolation)
    }

    @Test("Both directions are available with nothing selected")
    func testNoSelection() async throws {
        let viewModel = try await makeViewModel(violationCount: 3)
        viewModel.selectedViolationId = nil
        #expect(viewModel.canSelectPreviousViolation)
        #expect(viewModel.canSelectNextViolation)
    }

    @Test("Previous is unavailable on the first violation")
    func testFirstSelected() async throws {
        let viewModel = try await makeViewModel(violationCount: 3)
        viewModel.selectedViolationId = viewModel.filteredViolations.first?.id
        #expect(!viewModel.canSelectPreviousViolation)
        #expect(viewModel.canSelectNextViolation)
    }

    @Test("Next is unavailable on the last violation")
    func testLastSelected() async throws {
        let viewModel = try await makeViewModel(violationCount: 3)
        viewModel.selectedViolationId = viewModel.filteredViolations.last?.id
        #expect(viewModel.canSelectPreviousViolation)
        #expect(!viewModel.canSelectNextViolation)
    }

    @Test("Both directions are available in the middle")
    func testMiddleSelected() async throws {
        let viewModel = try await makeViewModel(violationCount: 3)
        viewModel.selectedViolationId = viewModel.filteredViolations[1].id
        #expect(viewModel.canSelectPreviousViolation)
        #expect(viewModel.canSelectNextViolation)
    }

    @Test("Neither direction is available with a single violation selected")
    func testSingleViolationSelected() async throws {
        let viewModel = try await makeViewModel(violationCount: 1)
        viewModel.selectedViolationId = viewModel.filteredViolations.first?.id
        #expect(!viewModel.canSelectPreviousViolation)
        #expect(!viewModel.canSelectNextViolation)
    }

    @Test("Availability matches what the navigation methods do at each end")
    func testAvailabilityMatchesNavigation() async throws {
        let viewModel = try await makeViewModel(violationCount: 3)
        let lastId = viewModel.filteredViolations.last?.id
        viewModel.selectedViolationId = lastId
        viewModel.selectNextViolation()
        #expect(viewModel.selectedViolationId == lastId, "Next on the last violation does nothing")

        let firstId = viewModel.filteredViolations.first?.id
        viewModel.selectedViolationId = firstId
        viewModel.selectPreviousViolation()
        #expect(viewModel.selectedViolationId == firstId, "Previous on the first violation does nothing")
    }
}
