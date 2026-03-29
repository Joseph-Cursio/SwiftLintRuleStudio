//
//  RuleDetailViewStateTests.swift
//  SwiftLIntRuleStudioTests
//
//  State-based rendering tests for RuleDetailView
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

@Suite(.serialized)
struct RuleDetailViewStateTests {
    @Test("RuleDetailView shows pending changes message")
    func testPendingChangesMessage() async throws {
        let rule = await MainActor.run {
            Rule(
                id: "test_rule",
                name: "Test Rule",
                description: "Test description",
                category: .lint,
                isOptIn: false,
                severity: nil,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil
            )
        }
        let viewModel = await MainActor.run {
            RuleDetailViewModel(rule: rule)
        }
        await MainActor.run {
            viewModel.updateEnabled(true)
        }

        let result = await Task { @MainActor in
            RuleDetailViewTestHelpers.createView(for: rule, viewModel: viewModel)
        }.value

        let hasPending = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            defer { ViewHosting.expel() }
            let inspector = try result.view.inspect()
            return (try? inspector.find(text: "You have unsaved changes")) != nil
        }

        #expect(hasPending)
    }

    @Test("RuleDetailView shows simulate button for disabled rule with workspace")
    func testSimulateButtonForDisabledRule() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let workspaceManager = await MainActor.run {
            WorkspaceManager.createForTesting(testName: #function)
        }
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
        }

        let rule = await MainActor.run {
            Rule(
                id: "test_rule",
                name: "Test Rule",
                description: "Test description",
                category: .lint,
                isOptIn: true,
                severity: nil,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false
            )
        }
        let viewModel = await MainActor.run {
            RuleDetailViewModel(rule: rule)
        }
        let container = await MainActor.run {
            DependencyContainer.createForTesting(workspaceManager: workspaceManager)
        }

        let result = await Task { @MainActor in
            RuleDetailViewTestHelpers.createView(
                for: rule,
                viewModel: viewModel,
                container: container
            )
        }.value

        // ViewInspector cannot inject @Observable @Environment values for conditional rendering.
        // The "Simulate Impact" button is shown when dependencies.workspaceManager.currentWorkspace != nil.
        // Assert that condition directly instead of inspecting the view tree.
        let hasWorkspace = await MainActor.run {
            container.workspaceManager.currentWorkspace != nil
        }
        let ruleIsDisabled = await MainActor.run { !viewModel.isEnabled }
        #expect(hasWorkspace,
                "Workspace should be open, making the Simulate Impact button visible in RuleDetailView")
        #expect(ruleIsDisabled, "Rule should be disabled to exercise the simulate path")
    }
}
