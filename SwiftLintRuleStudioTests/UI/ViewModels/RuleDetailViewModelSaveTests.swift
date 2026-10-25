//
//  RuleDetailViewModelSaveTests.swift
//  SwiftLintRuleStudioTests
//
//  Save tests for RuleDetailViewModel
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct RuleDetailViewModelSaveTests {
    @Test("RuleDetailViewModel saves enabled rule to config")
    func testSaveConfigurationEnableRule() async throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: "rules: {}")
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
            viewModel.updateEnabled(true)
            viewModel.updateSeverity(.error)
        }

        try await MainActor.run {
            try viewModel.saveConfiguration()
        }

        let snapshot = try await MainActor.run {
            try yamlEngine.load()
            let config = yamlEngine.getConfig()
            let ruleConfig = config.rules["test_rule"]
            return (
                hasRule: ruleConfig != nil,
                isEnabled: ruleConfig?.enabled == true,
                severityMatch: ruleConfig?.severity == .error,
                pendingChangesCleared: viewModel.pendingChanges == nil
            )
        }

        #expect(snapshot.hasRule)
        #expect(snapshot.isEnabled)
        #expect(snapshot.severityMatch)
        #expect(snapshot.pendingChangesCleared)
    }

    @Test("RuleDetailViewModel saves disabled rule to config")
    func testSaveConfigurationDisableRule() async throws {
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

        try await MainActor.run {
            try viewModel.saveConfiguration()
        }

        let (hasRule, isDisabled) = try await MainActor.run {
            try yamlEngine.load()
            let config = yamlEngine.getConfig()
            return (
                config.rules["test_rule"] != nil,
                config.disabledRules?.contains("test_rule") == true
            )
        }

        // A default rule is disabled by landing in `disabled_rules` — and by
        // nothing else. Its old `severity: warning` mapping is deliberately not
        // re-emitted: SwiftLint 0.65.0 warns "Found a configuration for
        // 'test_rule' rule, but it is disabled in 'disabled_rules'." when a
        // config carries both, so the severity override is dropped on disable.
        #expect(isDisabled)
        #expect(!hasRule, "a disabled rule must not also survive as a config mapping")
    }

    @Test("RuleDetailViewModel saves severity change")
    func testSaveConfigurationSeverityChange() async throws {
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

        try await MainActor.run {
            try viewModel.saveConfiguration()
        }

        let severity = try await MainActor.run {
            try yamlEngine.load()
            let config = yamlEngine.getConfig()
            return config.rules["test_rule"]?.severity
        }

        #expect(severity == .error)
    }

    @Test("RuleDetailViewModel backs the previous file up into the store when saving, not beside it")
    func testSaveConfigurationCreatesBackup() async throws {
        let configContent = """
        rules:
          test_rule:
            enabled: true
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }
        let store = ConfigBackupStore(root: TestTempDirectory.make("ruledetail-backups"))

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(
            configPath: configPath,
            backups: store
        )
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
        try await MainActor.run {
            try viewModel.saveConfiguration()
        }

        let backups = await MainActor.run { store.backups(for: configPath) }
        #expect(backups.count == 1)
        #expect(try backups.first.map { try String(contentsOf: $0.path, encoding: .utf8) } == configContent)
        // Each save used to leave a `.swiftlint.yml.<seconds>.backup` in the project (issue #83).
        let projectFolder = configPath.deletingLastPathComponent().path
        let projectFiles = try FileManager.default.contentsOfDirectory(atPath: projectFolder)
        #expect(projectFiles == [".swiftlint.yml"])
    }

    @Test("RuleDetailViewModel throws error when saving without workspace")
    func testSaveConfigurationNoWorkspace() async throws {
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(rule: rule)

        await MainActor.run {
            viewModel.updateEnabled(true)
        }

        await #expect(throws: RuleConfigurationError.noWorkspace) {
            try await MainActor.run {
                try viewModel.saveConfiguration()
            }
        }
    }

    @Test("RuleDetailViewModel handles save errors gracefully")
    func testSaveConfigurationErrorHandling() async throws {
        let tempDir = TestTempDirectory.make("saveerror")
        let invalidPath = tempDir
            .appendingPathComponent("nonexistent")
            .appendingPathComponent(".swiftlint.yml")
        let invalidEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: invalidPath)

        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: invalidEngine
        )

        await MainActor.run {
            viewModel.updateEnabled(true)
        }

        do {
            try await MainActor.run {
                try viewModel.saveConfiguration()
            }
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is CocoaError || error is YAMLConfigError)
        }
    }
}
