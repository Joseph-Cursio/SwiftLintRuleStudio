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

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        await MainActor.run {
            viewModel.updateEnabled(false)
        }

        let (hasPendingChanges, enabled) = await MainActor.run {
            (viewModel.pendingChanges != nil, viewModel.pendingChanges?.enabled)
        }

        #expect(hasPendingChanges)
        #expect(enabled == false)
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

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        await MainActor.run {
            viewModel.updateSeverity(.error)
        }

        let (hasPendingChanges, severity) = await MainActor.run {
            (viewModel.pendingChanges != nil, viewModel.pendingChanges?.severity)
        }

        #expect(hasPendingChanges)
        #expect(severity == .error)
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

        try await MainActor.run {
            try viewModel.loadConfiguration()
            viewModel.updateEnabled(false)
        }

        await MainActor.run {
            viewModel.cancelChanges()
        }

        let (isEnabled, severity, pendingChanges) = await MainActor.run {
            (viewModel.isEnabled, viewModel.severity, viewModel.pendingChanges)
        }

        #expect(isEnabled)
        #expect(severity == .error)
        #expect(pendingChanges == nil)
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

        await MainActor.run {
            viewModel.updateEnabled(true)
            viewModel.showPreview()
        }

        let (showDiffPreview, pendingChanges) = await MainActor.run {
            (viewModel.showDiffPreview, viewModel.pendingChanges)
        }

        #expect(showDiffPreview)
        #expect(pendingChanges != nil)
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

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        await MainActor.run {
            viewModel.updateEnabled(false)
        }
        let hasPendingAfterChange = await MainActor.run { viewModel.pendingChanges != nil }
        #expect(hasPendingAfterChange)

        await MainActor.run {
            viewModel.updateEnabled(true)
        }
        let hasPendingAfterRevert = await MainActor.run { viewModel.pendingChanges == nil }
        #expect(hasPendingAfterRevert)
    }
}
