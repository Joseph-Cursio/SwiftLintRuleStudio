//
//  RuleBrowserViewModelBulkErrorTests.swift
//  SwiftLintRuleStudioTests
//
//  Regression for P2.3: bulk rule ops began with
//  `guard (try? yamlEngine.load()) != nil else { return }`, so a malformed
//  .swiftlint.yml made Enable/Disable/Set-Severity do nothing with zero feedback.
//  The load failure must now be surfaced via `bulkOperationError`.
//

import Foundation
import SwiftLintCLIBackend
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct RuleBrowserViewModelBulkErrorTests {
    private static func makeViewModel() -> RuleBrowserViewModel {
        let cacheManager = CacheManager()
        let cli = SwiftLintCLIActor(cacheManager: cacheManager)
        let registry = RuleRegistry(swiftLintCLI: cli, cacheManager: cacheManager)
        registry.setRulesForTesting([
            Rule(
                id: "force_cast", name: "Force Cast", description: "Avoid force casting",
                category: .style, isOptIn: false, severity: .warning, parameters: nil,
                triggeringExamples: [], nonTriggeringExamples: [], documentation: nil,
                isEnabled: true, supportsAutocorrection: false
            )
        ])
        return RuleBrowserViewModel(ruleRegistry: registry)
    }

    @Test("Bulk enable surfaces an error when the config fails to load")
    func testBulkEnableSurfacesLoadError() throws {
        // An unterminated flow sequence — Yams rejects it, so load() throws.
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: "foo: [1, 2, 3")
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
        let viewModel = Self.makeViewModel()
        viewModel.selectedRuleIds = ["force_cast"]
        viewModel.enableSelectedRules(yamlEngine: yamlEngine)

        #expect(viewModel.bulkDiff == nil, "no diff should be produced when the config can't load")
        #expect(viewModel.bulkOperationError != nil, "a config-load failure must be surfaced to the user")
    }

    @Test("A successful bulk op clears any lingering error")
    func testBulkOpClearsError() throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: "excluded:\n  - .build\n")
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
        let viewModel = Self.makeViewModel()
        viewModel.bulkOperationError = "stale error from a previous attempt"
        viewModel.selectedRuleIds = ["force_cast"]
        viewModel.enableSelectedRules(yamlEngine: yamlEngine)

        #expect(viewModel.bulkDiff != nil)
        #expect(viewModel.bulkOperationError == nil, "a clean op must clear any prior error")
    }
}
