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
        let view = result.view

        nonisolated(unsafe) let viewCapture = view
        let hasPending = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            let inspector = try viewCapture.inspect()
            return (try? inspector.find(text: "You have unsaved changes")) != nil
        }

        #expect(hasPending == true)
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
            RuleDetailViewModel(rule: rule, workspaceManager: workspaceManager)
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
        let view = result.view

        nonisolated(unsafe) let viewCapture = view
        let hasSimulate = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            let inspector = try viewCapture.inspect()
            return (try? inspector.find(text: "Simulate Impact")) != nil
        }

        #expect(hasSimulate == true)
    }
}
