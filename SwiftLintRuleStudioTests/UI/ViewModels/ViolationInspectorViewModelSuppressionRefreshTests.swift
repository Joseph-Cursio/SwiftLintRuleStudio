//
//  ViolationInspectorViewModelSuppressionRefreshTests.swift
//  SwiftLintRuleStudioTests
//
//  Regression tests for P0.1 (Part B): suppress/resolve are DB mutations, so the
//  list must be repainted from storage — NOT by re-running a full workspace
//  analysis. Re-analyzing on every suppress was both wasteful and, before the
//  storage upsert, actively discarded the user's decision.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct ViolationInspectorViewModelSuppressionRefreshTests {
    private static func makeWorkspace() -> Workspace {
        let tempPath = TestTempDirectory.make("suppression-workspace")
        return Workspace(path: tempPath)
    }

    @Test("Suppressing violations repaints from storage without re-running analysis")
    func suppressDoesNotReanalyze() async throws {
        let storage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let analyzer = MockWorkspaceAnalyzer(mockStorage: storage)
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: storage,
            workspaceAnalyzer: analyzer
        )

        let workspace = Self.makeWorkspace()
        let violation = ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1")
        analyzer.mockViolations = [violation]

        // Initial load runs analysis exactly once.
        try await viewModel.loadViolations(for: workspace.id, workspace: workspace)
        let callsAfterLoad = analyzer.analyzeCallCount
        #expect(callsAfterLoad == 1)

        viewModel.selectedViolationIds = [violation.id]
        try await viewModel.suppressSelectedViolations(reason: "not applicable")

        // Suppression must NOT trigger another analysis...
        #expect(analyzer.analyzeCallCount == callsAfterLoad)
        // ...and the list must reflect the suppression, read back from storage.
        #expect(viewModel.violations.contains { $0.id == violation.id && $0.suppressed })
        #expect(viewModel.selectedViolationIds.isEmpty)
    }

    @Test("Resolving violations repaints from storage without re-running analysis")
    func resolveDoesNotReanalyze() async throws {
        let storage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let analyzer = MockWorkspaceAnalyzer(mockStorage: storage)
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: storage,
            workspaceAnalyzer: analyzer
        )

        let workspace = Self.makeWorkspace()
        let violation = ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1")
        analyzer.mockViolations = [violation]

        try await viewModel.loadViolations(for: workspace.id, workspace: workspace)
        let callsAfterLoad = analyzer.analyzeCallCount
        #expect(callsAfterLoad == 1)

        viewModel.selectedViolationIds = [violation.id]
        try await viewModel.resolveSelectedViolations()

        // Resolution must NOT trigger another analysis...
        #expect(analyzer.analyzeCallCount == callsAfterLoad)
        // ...and the list must reflect the resolution, read back from storage.
        #expect(viewModel.violations.contains { $0.id == violation.id && $0.resolvedAt != nil })
        #expect(viewModel.selectedViolationIds.isEmpty)
    }
}
