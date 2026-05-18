//
//  RuleBrowserViewModelBulkTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for bulk rule operations in RuleBrowserViewModel
//

import Testing
import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

@MainActor
struct RuleBrowserViewModelBulkTests {

    // MARK: - Helpers

    @MainActor
    private static func createTestViewModel() -> RuleBrowserViewModel {
        let cacheManager = CacheManager()
        let cli = SwiftLintCLIActor(cacheManager: cacheManager)
        let registry = RuleRegistry(swiftLintCLI: cli, cacheManager: cacheManager)

        // Add test rules
        registry.setRulesForTesting([
            Rule(
                id: "force_cast", name: "Force Cast", description: "Avoid force casting",
                category: .style, isOptIn: false, severity: .warning, parameters: nil,
                triggeringExamples: [], nonTriggeringExamples: [], documentation: nil,
                isEnabled: true, supportsAutocorrection: false
            ),
            Rule(
                id: "line_length", name: "Line Length", description: "Limit line length",
                category: .metrics, isOptIn: false, severity: .warning, parameters: nil,
                triggeringExamples: [], nonTriggeringExamples: [], documentation: nil,
                isEnabled: false, supportsAutocorrection: false
            ),
            Rule(
                id: "trailing_whitespace", name: "Trailing Whitespace", description: "No trailing whitespace",
                category: .style, isOptIn: false, severity: .warning, parameters: nil,
                triggeringExamples: [], nonTriggeringExamples: [], documentation: nil,
                isEnabled: true, supportsAutocorrection: true
            )
        ])

        return RuleBrowserViewModel(ruleRegistry: registry)
    }

    // MARK: - Selection Tests

    @Test("Toggle multi-select mode")
    func testToggleMultiSelect() async throws {
        await MainActor.run {
            let viewModel = Self.createTestViewModel()
            #expect(viewModel.isMultiSelectMode == false)
            viewModel.toggleMultiSelect()
            #expect(viewModel.isMultiSelectMode)
            viewModel.toggleMultiSelect()
            #expect(viewModel.isMultiSelectMode == false)
        }
    }

    @Test("Toggle rule selection")
    func testToggleRuleSelection() async throws {
        await MainActor.run {
            let viewModel = Self.createTestViewModel()
            viewModel.toggleRuleSelection("force_cast")
            #expect(viewModel.selectedRuleIds.contains("force_cast"))

            viewModel.toggleRuleSelection("force_cast")
            #expect(viewModel.selectedRuleIds.contains("force_cast") == false)
        }
    }

    @Test("Select all filtered rules")
    func testSelectAllFiltered() async throws {
        await MainActor.run {
            let viewModel = Self.createTestViewModel()
            viewModel.selectAllFiltered()
            #expect(viewModel.selectedRuleIds.count == 3)
            #expect(viewModel.selectedRuleIds.contains("force_cast"))
            #expect(viewModel.selectedRuleIds.contains("line_length"))
            #expect(viewModel.selectedRuleIds.contains("trailing_whitespace"))
        }
    }

    @Test("Clear selection")
    func testClearSelection() async throws {
        await MainActor.run {
            let viewModel = Self.createTestViewModel()
            viewModel.selectAllFiltered()
            #expect(viewModel.selectedRuleIds.count == 3)

            viewModel.clearSelection()
            #expect(viewModel.selectedRuleIds.isEmpty)
        }
    }

    @Test("Exit multi-select clears selection")
    func testExitMultiSelectClearsSelection() async throws {
        await MainActor.run {
            let viewModel = Self.createTestViewModel()
            viewModel.toggleMultiSelect()
            viewModel.selectAllFiltered()
            #expect(viewModel.selectedRuleIds.count == 3)

            viewModel.toggleMultiSelect()
            #expect(viewModel.selectedRuleIds.isEmpty)
        }
    }

    // MARK: - Bulk Operation Tests

    @Test("Bulk enable generates diff")
    func testBulkEnableGeneratesDiff() async throws {
        let configContent = """
        rules:
          force_cast:
            enabled: false
          line_length:
            enabled: false
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        await MainActor.run {
            let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
            let viewModel = Self.createTestViewModel()
            viewModel.selectedRuleIds = Set(["force_cast", "line_length"])
            viewModel.enableSelectedRules(yamlEngine: yamlEngine)

            let diff = viewModel.bulkDiff
            #expect(diff != nil)
            #expect(diff?.hasChanges == true)
        }
    }

    @Test("Bulk disable generates diff")
    func testBulkDisableGeneratesDiff() async throws {
        let configContent = """
        rules:
          force_cast:
            enabled: true
          line_length:
            enabled: true
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        await MainActor.run {
            let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
            let viewModel = Self.createTestViewModel()
            viewModel.selectedRuleIds = Set(["force_cast", "line_length"])
            viewModel.disableSelectedRules(yamlEngine: yamlEngine)

            let diff = viewModel.bulkDiff
            #expect(diff != nil)
            #expect(diff?.hasChanges == true)
        }
    }

    @Test("Bulk severity change generates diff")
    func testBulkSeverityChangeGeneratesDiff() async throws {
        let configContent = """
        rules:
          force_cast:
            severity: warning
          line_length:
            severity: warning
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        await MainActor.run {
            let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
            let viewModel = Self.createTestViewModel()
            viewModel.selectedRuleIds = Set(["force_cast", "line_length"])
            viewModel.setSeverityForSelected(.error, yamlEngine: yamlEngine)

            let diff = viewModel.bulkDiff
            #expect(diff != nil)
            #expect(diff?.modifiedRules.contains("force_cast") == true)
            #expect(diff?.modifiedRules.contains("line_length") == true)
        }
    }

    @MainActor
    private static func createTestViewModelWithMixedRules() -> RuleBrowserViewModel {
        let cacheManager = CacheManager()
        let cli = SwiftLintCLIActor(cacheManager: cacheManager)
        let registry = RuleRegistry(swiftLintCLI: cli, cacheManager: cacheManager)

        registry.setRulesForTesting([
            // Default-enabled rule
            Rule(
                id: "force_cast", name: "Force Cast", description: "Avoid force casting",
                category: .style, isOptIn: false, isAnalyzer: false, severity: .warning,
                parameters: nil, triggeringExamples: [], nonTriggeringExamples: [], documentation: nil,
                isEnabled: false, supportsAutocorrection: false
            ),
            // Opt-in rule
            Rule(
                id: "explicit_init", name: "Explicit Init", description: "Use explicit init",
                category: .style, isOptIn: true, isAnalyzer: false, severity: .warning,
                parameters: nil, triggeringExamples: [], nonTriggeringExamples: [], documentation: nil,
                isEnabled: false, supportsAutocorrection: false
            ),
            // Analyzer-only rule
            Rule(
                id: "unused_declaration", name: "Unused Declaration", description: "Detect unused decls",
                category: .lint, isOptIn: false, isAnalyzer: true, severity: .warning,
                parameters: nil, triggeringExamples: [], nonTriggeringExamples: [], documentation: nil,
                isEnabled: false, supportsAutocorrection: false
            )
        ])

        return RuleBrowserViewModel(ruleRegistry: registry)
    }

    @Test("Bulk enable routes analyzer rule into analyzer_rules and opt-in into opt_in_rules")
    func testBulkEnableRoutesAnalyzerAndOptInCorrectly() async throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: "rules: {}")
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        try await MainActor.run {
            let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
            let viewModel = Self.createTestViewModelWithMixedRules()
            viewModel.selectedRuleIds = Set(["force_cast", "explicit_init", "unused_declaration"])
            viewModel.enableSelectedRules(yamlEngine: yamlEngine)
            try viewModel.saveBulkChanges(yamlEngine: yamlEngine)
        }

        let lists = try await MainActor.run { () -> RuleListSnapshot in
            let engine = YAMLConfigurationEngine(configPath: configPath)
            try engine.load()
            let config = engine.getConfig()
            return RuleListSnapshot(
                analyzer: config.analyzerRules,
                optIn: config.optInRules,
                disabled: config.disabledRules
            )
        }

        // Analyzer rule goes only to analyzer_rules
        #expect(lists.analyzer?.contains("unused_declaration") == true)
        #expect(lists.optIn?.contains("unused_declaration") != true)
        // Opt-in rule goes only to opt_in_rules
        #expect(lists.optIn?.contains("explicit_init") == true)
        #expect(lists.analyzer?.contains("explicit_init") != true)
        // Default-enabled rule is in neither list
        #expect(lists.analyzer?.contains("force_cast") != true)
        #expect(lists.optIn?.contains("force_cast") != true)
        // None of them ended up in disabled_rules
        #expect(lists.disabled?.contains("force_cast") != true)
        #expect(lists.disabled?.contains("explicit_init") != true)
        #expect(lists.disabled?.contains("unused_declaration") != true)
    }

    @Test("Save bulk changes persists to file")
    func testSaveBulkChanges() async throws {
        let configContent = """
        rules:
          force_cast:
            severity: warning
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        try await MainActor.run {
            let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
            let viewModel = Self.createTestViewModel()
            viewModel.selectedRuleIds = Set(["force_cast"])
            viewModel.setSeverityForSelected(.error, yamlEngine: yamlEngine)
            try viewModel.saveBulkChanges(yamlEngine: yamlEngine)

            // Diff cleared after save
            #expect(viewModel.bulkDiff == nil)
        }

        let saved = try String(contentsOf: configPath, encoding: .utf8)
        #expect(saved.contains("error"))
    }
}

private struct RuleListSnapshot {
    let analyzer: [String]?
    let optIn: [String]?
    let disabled: [String]?
}
