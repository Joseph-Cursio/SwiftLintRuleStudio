//
//  ViolationInspectorViewModelSelectionClearingTests.swift
//  SwiftLintRuleStudioTests
//
//  Regression for P3: suppress/resolve cleared the *live* selection at completion
//  (removeAll), so a selection the user made while the async call was in flight was
//  wiped. Only the processed ids should be cleared.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct ViolationInspectorViewModelSelectionClearingTests {
    @Test("Suppress clears only processed ids, preserving a mid-flight selection")
    func suppressPreservesMidFlightSelection() async throws {
        let storage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: storage
        )
        let workspaceId = UUID()
        let violationA = ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "a")
        let violationB = ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "b")
        let violationC = ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "c")
        try await storage.storeViolations([violationA, violationB, violationC], for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        viewModel.selectedViolationIds = [violationA.id, violationB.id]
        // Simulate the user selecting C while the suppress is in flight (during the
        // repaint's fetch). C is a real stored violation, so it survives the repaint.
        storage.onFetch = {
            MainActor.assumeIsolated {
                _ = viewModel.selectedViolationIds.insert(violationC.id)
            }
        }

        try await viewModel.suppressSelectedViolations(reason: "not applicable")

        #expect(
            viewModel.selectedViolationIds == [violationC.id],
            "only the processed ids should clear; the mid-flight selection must survive"
        )
    }

    @Test("Resolve clears only processed ids, preserving a mid-flight selection")
    func resolvePreservesMidFlightSelection() async throws {
        let storage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: storage
        )
        let workspaceId = UUID()
        let violationA = ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "a")
        let violationC = ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "c")
        try await storage.storeViolations([violationA, violationC], for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        viewModel.selectedViolationIds = [violationA.id]
        storage.onFetch = {
            MainActor.assumeIsolated {
                _ = viewModel.selectedViolationIds.insert(violationC.id)
            }
        }

        try await viewModel.resolveSelectedViolations()

        #expect(viewModel.selectedViolationIds == [violationC.id])
    }
}
