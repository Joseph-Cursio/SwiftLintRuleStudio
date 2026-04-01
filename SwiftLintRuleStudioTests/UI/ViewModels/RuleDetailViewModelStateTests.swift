//
//  RuleDetailViewModelStateTests.swift
//  SwiftLintRuleStudioTests
//
//  State update tests for RuleDetailViewModel
//

import Testing
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

@MainActor
struct RuleDetailViewModelStateTests {
    @Test("RuleDetailViewModel tracks pending changes when enabled state changes")
    func testUpdateEnabledTracksChanges() async throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: "")
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try viewModel.loadConfiguration()
        viewModel.updateEnabled(false)

        #expect(viewModel.pendingChanges != nil)
        #expect(viewModel.pendingChanges?.enabled == false)
    }

    @Test("RuleDetailViewModel tracks pending changes when severity changes")
    func testUpdateSeverityTracksChanges() async throws {
        let configContent = """
        rules:
          test_rule:
            enabled: true
            severity: warning
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try viewModel.loadConfiguration()
        viewModel.updateSeverity(.error)

        #expect(viewModel.pendingChanges != nil)
        #expect(viewModel.pendingChanges?.severity == .error)
    }

    @Test("RuleDetailViewModel cancelChanges reloads original state")
    func testCancelChangesReloadsState() async throws {
        let configContent = """
        rules:
          test_rule:
            enabled: true
            severity: error
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try viewModel.loadConfiguration()
        viewModel.updateEnabled(false)
        viewModel.cancelChanges()

        #expect(viewModel.isEnabled)
        #expect(viewModel.severity == .error)
        #expect(viewModel.pendingChanges == nil)
    }

    @Test("RuleDetailViewModel showPreview sets flag")
    func testShowPreviewSetsFlag() async throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: "")
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        viewModel.updateEnabled(true)
        viewModel.showPreview()

        #expect(viewModel.showDiffPreview)
        #expect(viewModel.pendingChanges != nil)
    }

    @Test("RuleDetailViewModel clears pending changes when reverted")
    func testPendingChangesClearedOnRevert() async throws {
        let configContent = """
        rules:
          test_rule:
            enabled: true
            severity: warning
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try viewModel.loadConfiguration()
        viewModel.updateEnabled(false)
        #expect(viewModel.pendingChanges != nil)

        viewModel.updateEnabled(true)
        #expect(viewModel.pendingChanges == nil)
    }
}
