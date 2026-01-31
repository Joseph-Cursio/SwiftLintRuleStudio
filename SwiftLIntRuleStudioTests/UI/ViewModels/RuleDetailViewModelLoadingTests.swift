//
//  RuleDetailViewModelLoadingTests.swift
//  SwiftLIntRuleStudioTests
//
//  Configuration loading tests for RuleDetailViewModel
//

import Testing
@testable import SwiftLIntRuleStudio

struct RuleDetailViewModelLoadingTests {
    @Test("RuleDetailViewModel loads configuration from workspace")
    func testLoadConfiguration() async throws {
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
        }

        let (isEnabled, severity) = await MainActor.run {
            (viewModel.isEnabled, viewModel.severity)
        }

        #expect(isEnabled == true)
        #expect(severity == .error)
    }

    @Test("RuleDetailViewModel loads default state when rule not in config")
    func testLoadConfigurationRuleNotInConfig() async throws {
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

        let isEnabled = await MainActor.run { viewModel.isEnabled }
        #expect(isEnabled == true)
    }

    @Test("RuleDetailViewModel loads disabled state for opt-in rule not in config")
    func testLoadConfigurationOptInRuleNotInConfig() async throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: "rules: {}")
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "opt_in_rule", isOptIn: true)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        let isEnabled = await MainActor.run { viewModel.isEnabled }
        #expect(isEnabled == false)
    }

    @Test("RuleDetailViewModel honors only_rules when loading config")
    func testLoadConfigurationOnlyRules() async throws {
        let configContent = """
        only_rules:
          - special_rule
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "special_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        let (isEnabled, severity, defaultSeverity) = await MainActor.run {
            (viewModel.isEnabled, viewModel.severity, rule.defaultSeverity)
        }

        #expect(isEnabled == true)
        #expect(severity == defaultSeverity)
    }

    @Test("RuleDetailViewModel handles disabled_rules without explicit config")
    func testLoadConfigurationDisabledRules() async throws {
        let configContent = """
        disabled_rules:
          - disabled_rule
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "disabled_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        let (isEnabled, severity, defaultSeverity) = await MainActor.run {
            (viewModel.isEnabled, viewModel.severity, rule.defaultSeverity)
        }

        #expect(isEnabled == false)
        #expect(severity == defaultSeverity)
    }

    @Test("RuleDetailViewModel handles missing config file")
    func testLoadConfigurationMissingFile() async throws {
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

        let isEnabled = await MainActor.run { viewModel.isEnabled }
        #expect(isEnabled == true)
    }
}
