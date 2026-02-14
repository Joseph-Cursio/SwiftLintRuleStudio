//
//  RuleBrowserViewModelBulkTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for bulk rule operations in RuleBrowserViewModel
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

struct RuleBrowserViewModelBulkTests {

    // MARK: - Helpers

    @MainActor
    private static func createTestViewModel() -> RuleBrowserViewModel {
        let cacheManager = CacheManager()
        let cli = SwiftLintCLI(cacheManager: cacheManager)
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
            #expect(viewModel.isMultiSelectMode == true)
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
            #expect(!viewModel.selectedRuleIds.contains("force_cast"))
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
