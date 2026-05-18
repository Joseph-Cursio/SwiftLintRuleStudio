//
//  RuleDetailViewModelAnalyzerRoutingTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for analyzer / disabled-rule routing in RuleDetailViewModel
//

import Foundation
import Testing
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

@MainActor
struct RuleDetailViewModelAnalyzerRoutingTests {

    @Test("Disabling a default rule adds it to disabled_rules on save")
    func testDisableDefaultRuleAddsToDisabledRules() async throws {
        // Default-enabled rule with no analyzer / opt-in flag.
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: "rules: {}")
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(
            id: "default_rule",
            isOptIn: false,
            isAnalyzer: false
        )
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
            viewModel.updateEnabled(false)
            try viewModel.saveConfiguration()
        }

        let disabledRules = try await MainActor.run { () -> [String]? in
            try yamlEngine.load()
            return yamlEngine.getConfig().disabledRules
        }

        // The whole point of addDisabledRuleIfNeeded: default rules go into
        // disabled_rules when disabled.
        #expect(disabledRules?.contains("default_rule") == true)
    }

    @Test("Disabling an opt-in rule does NOT add it to disabled_rules")
    func testDisableOptInRuleSkipsDisabledRules() async throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: "opt_in_rules: [explicit_init]")
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(
            id: "explicit_init",
            isOptIn: true,
            isAnalyzer: false
        )
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
            viewModel.updateEnabled(false)
            try viewModel.saveConfiguration()
        }

        let snapshot = try await MainActor.run { () -> (disabled: [String]?, optIn: [String]?) in
            try yamlEngine.load()
            let config = yamlEngine.getConfig()
            return (config.disabledRules, config.optInRules)
        }

        // Opt-in rules are disabled by absence from opt_in_rules, not by
        // adding to disabled_rules.
        #expect(snapshot.disabled?.contains("explicit_init") != true)
        #expect(snapshot.optIn?.contains("explicit_init") != true)
    }

    @Test("Enabling an analyzer rule adds it to analyzer_rules, not opt_in_rules")
    func testEnableAnalyzerRuleAddsToAnalyzerRules() async throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: "rules: {}")
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(
            id: "unused_declaration",
            isOptIn: false,
            isAnalyzer: true
        )
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
            viewModel.updateEnabled(true)
            try viewModel.saveConfiguration()
        }

        let snapshot = try await MainActor.run { () -> (analyzer: [String]?, optIn: [String]?) in
            try yamlEngine.load()
            let config = yamlEngine.getConfig()
            return (config.analyzerRules, config.optInRules)
        }

        #expect(snapshot.analyzer?.contains("unused_declaration") == true)
        #expect(snapshot.optIn?.contains("unused_declaration") != true)
    }

    @Test("Disabling an analyzer rule removes it from analyzer_rules")
    func testDisableAnalyzerRuleRemovesFromAnalyzerRules() async throws {
        let configContent = """
        analyzer_rules:
          - unused_declaration
          - unused_import
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(
            id: "unused_declaration",
            isOptIn: false,
            isAnalyzer: true
        )
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
            viewModel.updateEnabled(false)
            try viewModel.saveConfiguration()
        }

        let snapshot = try await MainActor.run { () -> (analyzer: [String]?, disabled: [String]?) in
            try yamlEngine.load()
            let config = yamlEngine.getConfig()
            return (config.analyzerRules, config.disabledRules)
        }

        #expect(snapshot.analyzer?.contains("unused_declaration") != true)
        // Sibling analyzer rule untouched
        #expect(snapshot.analyzer?.contains("unused_import") == true)
        // Analyzer rules are disabled by absence, not by adding to disabled_rules
        #expect(snapshot.disabled?.contains("unused_declaration") != true)
    }

    @Test("Disabling sole analyzer rule clears the analyzer_rules list")
    func testDisableSoleAnalyzerRuleClearsList() async throws {
        let configContent = """
        analyzer_rules:
          - unused_declaration
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(
            id: "unused_declaration",
            isOptIn: false,
            isAnalyzer: true
        )
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
            viewModel.updateEnabled(false)
            try viewModel.saveConfiguration()
        }

        let analyzerRules = try await MainActor.run { () -> [String]? in
            try yamlEngine.load()
            return yamlEngine.getConfig().analyzerRules
        }

        // removeOptInRuleIfPresent collapses an emptied list to nil
        #expect(analyzerRules == nil)
    }
}
