import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct VIViewModelBulkOpsTests {
    @Test("ViolationInspectorViewModel suppresses selected violations")
    func testSuppressSelectedViolations() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violation1 = ViolationInspectorViewModelTestHelpers.createTestViolation(id: UUID(), ruleID: "rule1")
        let violation2 = ViolationInspectorViewModelTestHelpers.createTestViolation(id: UUID(), ruleID: "rule2")

        try await mockStorage.storeViolations([violation1, violation2], for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        let (violation1Id, violation2Id) = await MainActor.run {
            (violation1.id, violation2.id)
        }
        await MainActor.run {
            viewModel.selectedViolationIds = [violation1Id, violation2Id]
        }
        try await viewModel.suppressSelectedViolations(reason: "Test suppression")

        try await Task { @MainActor in
            try await viewModel.refreshViolations()
        }.value

        let (suppressedCount, selectedIdsEmpty) = await MainActor.run {
            let suppressed = viewModel.violations.filter { $0.suppressed }
            return (suppressed.count, viewModel.selectedViolationIds.isEmpty)
        }
        #expect(suppressedCount == 2)
        #expect(selectedIdsEmpty == true)
    }

    @Test("ViolationInspectorViewModel resolves selected violations")
    func testResolveSelectedViolations() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violation1 = ViolationInspectorViewModelTestHelpers.createTestViolation(id: UUID(), ruleID: "rule1")
        let violation2 = ViolationInspectorViewModelTestHelpers.createTestViolation(id: UUID(), ruleID: "rule2")

        try await mockStorage.storeViolations([violation1, violation2], for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        let (violation1Id, violation2Id) = await MainActor.run {
            (violation1.id, violation2.id)
        }
        await MainActor.run {
            viewModel.selectedViolationIds = [violation1Id, violation2Id]
        }
        try await viewModel.resolveSelectedViolations()

        try await Task { @MainActor in
            try await viewModel.refreshViolations()
        }.value

        let (resolvedCount, selectedIdsEmpty) = await MainActor.run {
            let resolved = viewModel.violations.filter { $0.resolvedAt != nil }
            return (resolved.count, viewModel.selectedViolationIds.isEmpty)
        }
        #expect(resolvedCount == 2)
        #expect(selectedIdsEmpty == true)
    }
}
