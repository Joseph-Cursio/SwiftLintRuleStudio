//
//  RuleDetailViewModelParameterTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for parameter editing in RuleDetailViewModel
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct RuleDetailViewModelParameterTests {

    // MARK: - Helper

    @MainActor
    private static func createRuleWithParameters() -> Rule {
        Rule(
            id: "line_length",
            name: "Line Length",
            description: "Lines should not span too many characters",
            category: .metrics,
            isOptIn: false,
            severity: .warning,
            parameters: [
                RuleParameter(
                    name: "warning", type: .integer,
                    defaultValue: AnyCodable(120), description: "Warning threshold"),
                RuleParameter(
                    name: "error", type: .integer,
                    defaultValue: AnyCodable(200), description: "Error threshold"),
                RuleParameter(
                    name: "ignores_urls", type: .boolean,
                    defaultValue: AnyCodable(true), description: "Ignore URLs")
            ],
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: true,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: .warning,
            markdownDocumentation: nil
        )
    }

    @Test("Load parameters from config")
    func testLoadParametersFromConfig() async throws {
        let configContent = """
        rules:
          line_length:
            warning: 100
            error: 150
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        try await MainActor.run {
            let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
            let rule = Self.createRuleWithParameters()

            // Verify the rule has parameters before creating the viewModel
            let params = try #require(rule.parameters, "Rule should have parameters")
            #expect(params.count == 3)

            let viewModel = RuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
            try viewModel.loadConfiguration()

            // Check that the engine loaded the rule config with params
            let engineConfig = yamlEngine.getConfig()
            let ruleConfig = try #require(engineConfig.rules["line_length"], "Expected line_length in config")
            #expect(ruleConfig.parameters != nil)

            // Verify viewModel parameter values
            let paramValues = viewModel.parameterValues
            #expect(paramValues.isEmpty == false, "Expected parameterValues to be populated")
        }
    }

    @Test("Update parameter triggers pending changes")
    func testUpdateParameterTriggersPendingChanges() async throws {
        let configContent = """
        rules:
          line_length:
            warning: 120
            error: 200
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = await Self.createRuleWithParameters()
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        // Initially no pending changes
        await MainActor.run {
            #expect(viewModel.pendingChanges == nil)
        }

        // Update a parameter
        await MainActor.run {
            viewModel.updateParameter("warning", value: AnyCodable(80))
        }

        try await MainActor.run {
            let changes = try #require(viewModel.pendingChanges, "Expected pending changes after parameter update")
            let warningParam = try #require(changes.parameters?["warning"], "Expected 'warning' parameter in changes")
            #expect(warningParam.value as? Int == 80)
        }
    }

    @Test("Diff includes parameter changes")
    func testDiffIncludesParameterChanges() async throws {
        let configContent = """
        rules:
          line_length:
            warning: 120
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = await Self.createRuleWithParameters()
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        await MainActor.run {
            viewModel.updateParameter("warning", value: AnyCodable(80))
        }

        try await MainActor.run {
            let diff = try #require(viewModel.generateDiff(), "Expected diff after parameter change")
            #expect(diff.modifiedRules.contains("line_length"))
        }
    }

    @Test("Save with parameters persists to YAML")
    func testSaveWithParameters() async throws {
        let configContent = """
        rules:
          line_length:
            warning: 120
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = await Self.createRuleWithParameters()
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
            viewModel.updateParameter("warning", value: AnyCodable(80))
            try viewModel.saveConfiguration()
        }

        // Verify saved content
        let savedContent = try String(contentsOf: configPath, encoding: .utf8)
        #expect(savedContent.contains("80"))

        // Verify pending changes cleared
        await MainActor.run {
            #expect(viewModel.pendingChanges == nil)
        }
    }

    @Test("Default parameter values from rule definition")
    func testDefaultParameterValues() async throws {
        let configContent = "rules: {}"
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = await Self.createRuleWithParameters()
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        await MainActor.run {
            let defaults = viewModel.defaultParameterValues()
            #expect(defaults["warning"]?.value as? Int == 120)
            #expect(defaults["error"]?.value as? Int == 200)
            #expect(defaults["ignores_urls"]?.value as? Bool == true)
        }
    }

    // MARK: - Load: no pre-fill of defaults

    @Test("Load with no YAML overrides leaves parameterValues empty")
    func testLoadWithoutOverridesLeavesParameterValuesEmpty() async throws {
        // No entry for `line_length` at all → no overrides in YAML.
        let configContent = "rules: {}"
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = await Self.createRuleWithParameters()
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
            // Previously this was pre-filled with all defaults; now it stays empty
            // so the editor's resolver supplies defaults at display time and
            // nothing redundant gets written back on save.
            #expect(viewModel.parameterValues.isEmpty)
        }
    }

    // MARK: - Save: strip default-equal entries

    @Test("parametersToPersist drops entries equal to defaults")
    func testParametersToPersistDropsDefaults() async throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: "rules: {}")
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = await Self.createRuleWithParameters()
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        await MainActor.run {
            // warning matches default (120), error overrides (180), ignores_urls
            // matches default (true). Only `error` should survive.
            viewModel.parameterValues = [
                "warning": AnyCodable(120),
                "error": AnyCodable(180),
                "ignores_urls": AnyCodable(true)
            ]
            let persistable = viewModel.parametersToPersist()
            #expect(persistable.count == 1)
            #expect(persistable["error"]?.value as? Int == 180)
            #expect(persistable["warning"] == nil)
            #expect(persistable["ignores_urls"] == nil)
        }
    }

    // MARK: - Binding-driven mutations trigger pendingChanges

    @Test("Direct assignment to parameterValues (binding path) triggers pendingChanges")
    func testParameterValuesBindingTriggersPendingChanges() async throws {
        // RuleParameterEditor edits viewModel.parameterValues via @Binding,
        // bypassing updateParameter(_:value:). This regression-tests that the
        // didSet on parameterValues still flags pending changes so the inline
        // Save/Discard buttons enable.
        let configContent = """
        rules:
          line_length:
            warning: 120
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = await Self.createRuleWithParameters()
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        await MainActor.run {
            #expect(viewModel.pendingChanges == nil)

            // Simulate the editor's binding mutating parameterValues directly.
            var newValues = viewModel.parameterValues
            newValues["warning"] = AnyCodable(80)
            viewModel.parameterValues = newValues

            #expect(viewModel.pendingChanges != nil)
            #expect(viewModel.pendingChanges?.parameters?["warning"]?.value as? Int == 80)
        }
    }

    @Test("Save with only default-equal overrides clears parameters block in YAML")
    func testSaveStripsAllDefaultsFromYAML() async throws {
        // Workspace has explicit overrides that happen to equal the defaults.
        // After saving with no further edits the YAML should no longer carry
        // the redundant parameters block.
        let configContent = """
        rules:
          line_length:
            warning: 120
            error: 200
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = await Self.createRuleWithParameters()
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
            // Force a save by faking a pending change (toggle severity, then back).
            // The persisted YAML should no longer contain 120/200 since both equal
            // the defaults and so are stripped.
            try viewModel.saveConfiguration()
        }

        let savedContent = try String(contentsOf: configPath, encoding: .utf8)
        // The block may still mention the rule (for `enabled`), but the param
        // values that match defaults should be gone.
        #expect(!savedContent.contains("warning: 120"))
        #expect(!savedContent.contains("error: 200"))
    }
}
