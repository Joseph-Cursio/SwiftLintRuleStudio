//
//  RuleDetailParameterDefaultsTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for how RuleDetailViewModel treats parameter values equal to the rule's defaults
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct RuleDetailParameterDefaultsTests {
    // MARK: - Load: no pre-fill of defaults

    @Test("Load with no YAML overrides leaves parameterValues empty")
    func testLoadWithoutOverridesLeavesParameterValuesEmpty() async throws {
        // No entry for `line_length` at all → no overrides in YAML.
        let configContent = "rules: {}"
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = await RuleDetailViewModelParameterTests.createRuleWithParameters()
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
        let rule = await RuleDetailViewModelParameterTests.createRuleWithParameters()
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
                "ignores_urls": AnyCodable(true),
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
        let rule = await RuleDetailViewModelParameterTests.createRuleWithParameters()
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
        let rule = await RuleDetailViewModelParameterTests.createRuleWithParameters()
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
