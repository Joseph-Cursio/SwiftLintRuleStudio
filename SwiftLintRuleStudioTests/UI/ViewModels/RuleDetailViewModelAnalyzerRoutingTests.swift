//
//  RuleDetailViewModelAnalyzerRoutingTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for analyzer / disabled-rule routing in RuleDetailViewModel
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

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

        // Without only_rules, a disabled default rule goes into disabled_rules.
        #expect(disabledRules?.contains("default_rule") == true)
    }

    @Test("Disabling an opt-in rule does NOT add it to disabled_rules")
    func testDisableOptInRuleSkipsDisabledRules() async throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(
            content: "opt_in_rules: [explicit_init]"
        )
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

        // An emptied list collapses to nil
        #expect(analyzerRules == nil)
    }

    // MARK: - Under only_rules (issue #83)

    /// Saves `rule` as `enabled` against `content`, returning the saved configuration, or the
    /// error the save threw — in which case the file must be untouched.
    private func save(
        _ rule: Rule,
        enabled: Bool,
        over content: String
    ) async throws -> Result<YAMLConfigurationEngine.YAMLConfig, Error> {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: content)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }
        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        do {
            try await MainActor.run {
                try viewModel.loadConfiguration()
                viewModel.updateEnabled(enabled)
                try viewModel.saveConfiguration()
            }
        } catch {
            #expect(try String(contentsOf: configPath, encoding: .utf8) == content)
            return .failure(error)
        }
        return .success(try await MainActor.run { try YAMLConfigurationEngine.loadConfig(at: configPath) })
    }

    @Test("Enabling an opt-in rule under only_rules adds it there alone, never to opt_in_rules")
    func testEnableOptInRuleUnderOnlyRules() async throws {
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "explicit_init", isOptIn: true)
        let config = try await save(rule, enabled: true, over: "only_rules:\n  - force_cast\n").get()

        #expect(config.onlyRules == ["force_cast", "explicit_init"])
        #expect(config.optInRules == nil)
    }

    @Test("Re-saving an opt-in rule already under only_rules adds no opt_in_rules")
    func testResaveOptInRuleUnderOnlyRules() async throws {
        // Any save of an enabled rule — a parameter edit, say — runs the enable path.
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "explicit_init", isOptIn: true)
        let config = try await save(rule, enabled: true, over: "only_rules:\n  - force_cast\n  - explicit_init\n").get()

        #expect(config.onlyRules == ["force_cast", "explicit_init"])
        #expect(config.optInRules == nil)
    }

    @Test("Enabling an analyzer rule under only_rules adds it to analyzer_rules alone")
    func testEnableAnalyzerRuleUnderOnlyRules() async throws {
        let rule = RuleDetailViewModelTestHelpers.createTestRule(
            id: "unused_declaration",
            isOptIn: true,
            isAnalyzer: true
        )
        let config = try await save(rule, enabled: true, over: "only_rules:\n  - force_cast\n").get()

        #expect(config.onlyRules == ["force_cast"])
        #expect(config.analyzerRules == ["unused_declaration"])
    }

    @Test("Disabling a default rule under only_rules takes it out, without disabled_rules")
    func testDisableDefaultRuleUnderOnlyRules() async throws {
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "line_length", isOptIn: false)
        let config = try await save(rule, enabled: false, over: "only_rules:\n  - force_cast\n  - line_length\n").get()

        #expect(config.onlyRules == ["force_cast"])
        #expect(config.disabledRules == nil)
    }

    @Test("Disabling the last only_rules rule is refused, not turned into every default rule")
    func testDisableLastOnlyRuleIsRefused() async throws {
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "force_cast", isOptIn: false)
        let result = try await save(rule, enabled: false, over: "only_rules:\n  - force_cast\n")

        guard case .failure(let error) = result else {
            Issue.record("expected the save to be refused")
            return
        }
        #expect(error is YAMLConfigError)
    }

    @Test("Saving into a file SwiftLint already rejects is refused")
    func testSaveIntoConflictedFileIsRefused() async throws {
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "line_length", isOptIn: false)
        let result = try await save(
            rule,
            enabled: true,
            over: "only_rules:\n  - force_cast\nopt_in_rules:\n  - explicit_init\n"
        )

        guard case .failure(let error) = result else {
            Issue.record("expected the save to be refused")
            return
        }
        #expect((error as? YAMLConfigError).map { if case .onlyRulesConflict = $0 { true } else { false } } == true)
    }
}
