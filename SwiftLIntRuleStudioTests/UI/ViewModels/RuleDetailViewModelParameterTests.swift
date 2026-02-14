//
//  RuleDetailViewModelParameterTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for parameter editing in RuleDetailViewModel
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

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
                RuleParameter(name: "warning", type: .integer, defaultValue: AnyCodable(120), description: "Warning threshold"),
                RuleParameter(name: "error", type: .integer, defaultValue: AnyCodable(200), description: "Error threshold"),
                RuleParameter(name: "ignores_urls", type: .boolean, defaultValue: AnyCodable(true), description: "Ignore URLs")
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
            #expect(rule.parameters != nil)
            #expect(rule.parameters?.count == 3)

            let viewModel = RuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
            try viewModel.loadConfiguration()

            // Check that the engine loaded the rule config with params
            let engineConfig = yamlEngine.getConfig()
            let ruleConfig = engineConfig.rules["line_length"]
            #expect(ruleConfig != nil)
            #expect(ruleConfig?.parameters != nil)

            // Verify viewModel parameter values
            let params = viewModel.parameterValues
            #expect(!params.isEmpty, "Expected parameterValues to be populated")
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

        await MainActor.run {
            let changes = viewModel.pendingChanges
            #expect(changes != nil)
            #expect(changes?.parameters?["warning"]?.value as? Int == 80)
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

        await MainActor.run {
            let diff = viewModel.generateDiff()
            #expect(diff != nil)
            #expect(diff?.modifiedRules.contains("line_length") == true)
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
}
