//
//  RuleDetailViewModelWorkflowIntegrationTests.swift
//  SwiftLIntRuleStudioTests
//
//  Full workflow integration tests
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct RuleDetailVMWorkflowIntegrationTests {
    @Test("Complete workflow: open workspace -> configure rule -> save -> verify")
    func testCompleteRuleConfigurationWorkflow() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let configPath = try RuleDetailVMIntegrationHelpers.createConfigFile(
            in: tempDir,
            content: """
            rules:
              existing_rule:
                enabled: true
                severity: warning
            """
        )

        let workspaceManager = await RuleDetailVMIntegrationHelpers.createWorkspaceManager()
        _ = try await openWorkspace(workspaceManager: workspaceManager, at: tempDir)

        let yamlEngine = await RuleDetailVMIntegrationHelpers.createYAMLConfigurationEngine(
            configPath: configPath
        )
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "new_rule", isOptIn: false)
        let viewModel = await RuleDetailVMIntegrationHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine,
            workspaceManager: workspaceManager
        )

        try await loadConfig(viewModel)
        await assertDefaults(viewModel)
        await updateSeverity(viewModel, severity: .error)
        await assertDiff(viewModel, expectsRule: "new_rule")
        try await saveConfig(viewModel)
        await assertPendingCleared(viewModel)

        try await Task { @MainActor in
            try yamlEngine.load()
        }.value
        let snapshot = await snapshotConfig(yamlEngine)
        assertSnapshot(snapshot)
    }

    @Test("Multiple rules configuration workflow")
    func testMultipleRulesConfigurationWorkflow() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let configPath = try RuleDetailVMIntegrationHelpers.createConfigFile(
            in: tempDir,
            content: "rules: {}"
        )
        let yamlEngine = await RuleDetailVMIntegrationHelpers.createYAMLConfigurationEngine(
            configPath: configPath
        )

        let viewModel1 = await makeViewModel(ruleId: "rule_1", yamlEngine: yamlEngine)
        try await configureRule(viewModel1, severity: .error, enabled: true)

        let viewModel2 = await makeViewModel(ruleId: "rule_2", yamlEngine: yamlEngine, isOptIn: true)
        try await configureRule(viewModel2, severity: .warning, enabled: true)

        try await Task { @MainActor in
            try yamlEngine.load()
        }.value
        let snapshot = await MainActor.run {
            let config = yamlEngine.getConfig()
            return (
                rule1Enabled: config.rules["rule_1"]?.enabled,
                rule1Severity: config.rules["rule_1"]?.severity,
                rule2Enabled: config.rules["rule_2"]?.enabled,
                rule2Severity: config.rules["rule_2"]?.severity
            )
        }
        #expect(snapshot.rule1Enabled == true)
        #expect(snapshot.rule1Severity == .error)
        #expect(snapshot.rule2Enabled == true)
        #expect(snapshot.rule2Severity == .warning)
    }

    @Test("Rule configuration persists across workspace reload")
    func testRuleConfigurationPersistsAcrossReload() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        let yamlEngine = await RuleDetailVMIntegrationHelpers.createYAMLConfigurationEngine(
            configPath: configPath
        )

        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailVMIntegrationHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )
        try await configureRule(viewModel, severity: .error, enabled: true)

        let yamlEngine2 = await RuleDetailVMIntegrationHelpers.createYAMLConfigurationEngine(
            configPath: configPath
        )
        try await Task { @MainActor in
            try yamlEngine2.load()
        }.value
        let snapshot = await MainActor.run {
            let config = yamlEngine2.getConfig()
            let hasRule = config.rules["test_rule"] != nil
            let isEnabled = config.rules["test_rule"]?.enabled
            let severity = config.rules["test_rule"]?.severity
            return (hasRule, isEnabled, severity)
        }
        #expect(snapshot.0 == true)
        #expect(snapshot.1 == true)
        #expect(snapshot.2 == .error)

        let viewModel2 = await RuleDetailVMIntegrationHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine2
        )
        try await loadConfig(viewModel2)
        let (isEnabled, severity) = await MainActor.run {
            (viewModel2.isEnabled, viewModel2.severity)
        }
        #expect(isEnabled == true)
        #expect(severity == .error)
    }

    private func openWorkspace(
        workspaceManager: WorkspaceManager,
        at url: URL
    ) async throws -> Workspace {
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: url)
            return try #require(workspaceManager.currentWorkspace)
        }
    }

    private func makeViewModel(
        ruleId: String,
        yamlEngine: YAMLConfigurationEngine,
        isOptIn: Bool = false
    ) async -> RuleDetailViewModel {
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: ruleId, isOptIn: isOptIn)
        return await RuleDetailVMIntegrationHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )
    }

    private func configureRule(
        _ viewModel: RuleDetailViewModel,
        severity: Severity,
        enabled: Bool
    ) async throws {
        try await Task { @MainActor in
            try viewModel.loadConfiguration()
            viewModel.updateEnabled(enabled)
            viewModel.updateSeverity(severity)
            try await viewModel.saveConfiguration()
        }.value
    }

    private func loadConfig(_ viewModel: RuleDetailViewModel) async throws {
        try await Task { @MainActor in
            try viewModel.loadConfiguration()
        }.value
    }

    private func assertDefaults(_ viewModel: RuleDetailViewModel) async {
        let (isEnabled, pending) = await MainActor.run {
            (viewModel.isEnabled, viewModel.pendingChanges)
        }
        #expect(isEnabled == true)
        #expect(pending == nil)
    }

    private func updateSeverity(_ viewModel: RuleDetailViewModel, severity: Severity) async {
        await MainActor.run {
            viewModel.updateSeverity(severity)
        }
    }

    private func assertDiff(_ viewModel: RuleDetailViewModel, expectsRule: String) async {
        let (hasDiff, hasNewRule) = await MainActor.run {
            let diff = viewModel.generateDiff()
            return (diff != nil, diff?.addedRules.contains(expectsRule) == true)
        }
        #expect(hasDiff == true)
        #expect(hasNewRule == true)
    }

    private func saveConfig(_ viewModel: RuleDetailViewModel) async throws {
        try await Task { @MainActor in
            try await viewModel.saveConfiguration()
        }.value
    }

    private func assertPendingCleared(_ viewModel: RuleDetailViewModel) async {
        let pending = await MainActor.run { viewModel.pendingChanges }
        #expect(pending == nil)
    }

    private struct RuleConfigSnapshot {
        let hasNewRule: Bool
        let newRuleEnabled: Bool?
        let newRuleSeverity: Severity?
        let hasExistingRule: Bool
        let existingRuleEnabled: Bool?
        let existingRuleSeverity: Severity?
    }

    private func snapshotConfig(_ yamlEngine: YAMLConfigurationEngine) async -> RuleConfigSnapshot {
        await MainActor.run {
            let config = yamlEngine.getConfig()
            return RuleConfigSnapshot(
                hasNewRule: config.rules["new_rule"] != nil,
                newRuleEnabled: config.rules["new_rule"]?.enabled,
                newRuleSeverity: config.rules["new_rule"]?.severity,
                hasExistingRule: config.rules["existing_rule"] != nil,
                existingRuleEnabled: config.rules["existing_rule"]?.enabled,
                existingRuleSeverity: config.rules["existing_rule"]?.severity
            )
        }
    }

    private func assertSnapshot(_ snapshot: RuleConfigSnapshot) {
        #expect(snapshot.hasNewRule == true)
        #expect(snapshot.newRuleEnabled == true)
        #expect(snapshot.newRuleSeverity == .error)
        #expect(snapshot.hasExistingRule == true)
        #expect(snapshot.existingRuleEnabled == true)
        #expect(snapshot.existingRuleSeverity == .warning)
    }
}
