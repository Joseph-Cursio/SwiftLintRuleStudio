//
//  RuleBrowserViewModelSyncTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests that Rule.isEnabled syncs with YAML config after changes
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

@MainActor
struct RuleBrowserViewModelSyncTests {

    private static func makeRegistry(with rules: [Rule]) -> RuleRegistry {
        let cache = CacheManager.createForTesting()
        let cli = SwiftLintCLIActor(cacheManager: cache)
        let registry = RuleRegistry(swiftLintCLI: cli, cacheManager: cache)
        registry.setRulesForTesting(rules)
        return registry
    }

    // MARK: - Enabled State Sync Tests

    @Test(
        "Disabled filter excludes rules after they are enabled in config"
    )
    func testDisabledFilterUpdatesAfterEnablingRule() throws {
        // Start with an opt-in rule that is disabled (isEnabled = false)
        let optInRule = Rule(
            id: "missing_docs",
            name: "Missing Docs",
            description: "Require docs",
            category: .lint,
            isOptIn: true,
            isEnabled: false
        )
        let defaultRule = Rule(
            id: "force_cast",
            name: "Force Cast",
            description: "Avoid force casts",
            category: .lint,
            isOptIn: false,
            isEnabled: true
        )

        let registry = Self.makeRegistry(with: [optInRule, defaultRule])
        let viewModel = RuleBrowserViewModel(ruleRegistry: registry)

        // Verify: filtering by disabled shows the opt-in rule
        viewModel.selectedStatus = .disabled
        #expect(
            viewModel.filteredRules.contains { $0.id == "missing_docs" },
            "missing_docs should appear in disabled filter initially"
        )

        // Now simulate enabling the rule in the YAML config
        let configContent = """
        opt_in_rules:
          - missing_docs
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(
            content: configContent
        )
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
        try yamlEngine.load()
        let config = yamlEngine.getConfig()

        // Sync enabled states from the YAML config
        registry.syncEnabledStates(with: config)

        // The rule should now be enabled in the registry
        let updatedRule = registry.rules.first { $0.id == "missing_docs" }
        #expect(
            updatedRule?.isEnabled == true,
            "missing_docs should be enabled after syncing with config"
        )

        // The disabled filter should no longer include this rule
        viewModel.selectedStatus = .disabled
        #expect(
            viewModel.filteredRules.contains { $0.id == "missing_docs" } == false,
            "missing_docs should NOT appear in disabled filter after being enabled"
        )

        // The enabled filter should now include it
        viewModel.selectedStatus = .enabled
        #expect(
            viewModel.filteredRules.contains { $0.id == "missing_docs" },
            "missing_docs should appear in enabled filter after being enabled"
        )
    }

    @Test(
        "Enabled filter excludes rules after they are disabled in config"
    )
    func testEnabledFilterUpdatesAfterDisablingRule() throws {
        // Start with a default rule that is enabled
        let defaultRule = Rule(
            id: "trailing_whitespace",
            name: "Trailing Whitespace",
            description: "No trailing whitespace",
            category: .style,
            isOptIn: false,
            isEnabled: true
        )

        let registry = Self.makeRegistry(with: [defaultRule])
        let viewModel = RuleBrowserViewModel(ruleRegistry: registry)

        // Verify: filtering by enabled shows the rule
        viewModel.selectedStatus = .enabled
        #expect(
            viewModel.filteredRules.contains { $0.id == "trailing_whitespace" },
            "trailing_whitespace should appear in enabled filter initially"
        )

        // Simulate disabling the rule in the YAML config
        let configContent = """
        disabled_rules:
          - trailing_whitespace
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(
            content: configContent
        )
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
        try yamlEngine.load()
        let config = yamlEngine.getConfig()

        registry.syncEnabledStates(with: config)

        // The rule should now be disabled
        let updatedRule = registry.rules.first {
            $0.id == "trailing_whitespace"
        }
        #expect(
            updatedRule?.isEnabled == false,
            "trailing_whitespace should be disabled after syncing with config"
        )

        // The enabled filter should no longer include this rule
        viewModel.selectedStatus = .enabled
        #expect(
            viewModel.filteredRules.contains {
                $0.id == "trailing_whitespace"
            } == false,
            "trailing_whitespace should NOT appear in enabled filter"
        )
    }

    @Test("Sync handles only_rules config mode")
    func testSyncWithOnlyRulesConfig() throws {
        let rules = [
            Rule(
                id: "force_cast",
                name: "Force Cast",
                description: "Avoid",
                category: .lint,
                isOptIn: false,
                isEnabled: true
            ),
            Rule(
                id: "line_length",
                name: "Line Length",
                description: "Limit",
                category: .metrics,
                isOptIn: false,
                isEnabled: true
            ),
            Rule(
                id: "missing_docs",
                name: "Missing Docs",
                description: "Require",
                category: .lint,
                isOptIn: true,
                isEnabled: false
            )
        ]

        let registry = Self.makeRegistry(with: rules)

        // only_rules means ONLY these rules are enabled
        let configContent = """
        only_rules:
          - force_cast
          - missing_docs
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(
            content: configContent
        )
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
        try yamlEngine.load()
        let config = yamlEngine.getConfig()

        registry.syncEnabledStates(with: config)

        // force_cast: in only_rules -> enabled
        #expect(registry.rules.first { $0.id == "force_cast" }?.isEnabled == true)
        // missing_docs: in only_rules -> enabled (even though opt-in)
        #expect(registry.rules.first { $0.id == "missing_docs" }?.isEnabled == true)
        // line_length: NOT in only_rules -> disabled
        #expect(registry.rules.first { $0.id == "line_length" }?.isEnabled == false)
    }
}
