//
//  RuleBrowserViewModelOnlyRulesTests.swift
//  SwiftLintRuleStudioTests
//
//  Bulk enable and disable under only_rules (issue #83): the Rule Browser used to put
//  opt-in rules in opt_in_rules and disabled rules in disabled_rules beside it, which
//  SwiftLint rejects.
//

import Foundation
import SwiftLintCLIBackend
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct RuleBrowserViewModelOnlyRulesTests {

    /// A default rule, an opt-in rule and an analyzer rule.
    private static func makeViewModel() -> RuleBrowserViewModel {
        let cacheManager = CacheManager()
        let cli = SwiftLintCLIActor(cacheManager: cacheManager)
        let registry = RuleRegistry(swiftLintCLI: cli, cacheManager: cacheManager)
        registry.setRulesForTesting([
            Rule(id: "force_cast", name: "Force Cast", description: "", category: .style, isOptIn: false),
            Rule(id: "explicit_init", name: "Explicit Init", description: "", category: .style, isOptIn: true),
            Rule(
                id: "unused_declaration", name: "Unused Declaration", description: "",
                category: .lint, isOptIn: true, isAnalyzer: true
            )
        ])
        return RuleBrowserViewModel(ruleRegistry: registry)
    }

    /// Runs a bulk enable or disable of `ruleIds` over `content` and returns the view model
    /// and the saved configuration (nil when no preview was produced).
    private func bulk(
        _ ruleIds: Set<String>,
        enable: Bool,
        over content: String
    ) async throws -> (viewModel: RuleBrowserViewModel, saved: YAMLConfigurationEngine.YAMLConfig?) {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: content)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        return try await MainActor.run {
            let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
            let viewModel = Self.makeViewModel()
            viewModel.selectedRuleIds = ruleIds
            if enable {
                viewModel.enableSelectedRules(yamlEngine: yamlEngine)
            } else {
                viewModel.disableSelectedRules(yamlEngine: yamlEngine)
            }
            guard viewModel.bulkDiff != nil else {
                #expect(try String(contentsOf: configPath, encoding: .utf8) == content)
                return (viewModel, nil)
            }
            try viewModel.saveBulkChanges(yamlEngine: yamlEngine)
            return (viewModel, try YAMLConfigurationEngine.loadConfig(at: configPath))
        }
    }

    @Test("Bulk enable under only_rules adds rules there, analyzer rules to analyzer_rules, nothing to opt_in_rules")
    func testBulkEnableUnderOnlyRules() async throws {
        let saved = try await bulk(
            ["explicit_init", "unused_declaration"],
            enable: true,
            over: "only_rules:\n  - force_cast\n"
        ).saved

        #expect(saved?.onlyRules == ["force_cast", "explicit_init"])
        #expect(saved?.analyzerRules == ["unused_declaration"])
        #expect(saved?.optInRules == nil)
    }

    @Test("Bulk disable under only_rules takes rules out, without disabled_rules")
    func testBulkDisableUnderOnlyRules() async throws {
        let saved = try await bulk(
            ["force_cast", "explicit_init"],
            enable: false,
            over: "only_rules:\n  - force_cast\n  - explicit_init\n  - line_length\n"
        ).saved

        #expect(saved?.onlyRules == ["line_length"])
        #expect(saved?.disabledRules == nil)
        #expect(saved?.optInRules == nil)
    }

    @Test("Bulk disable of every only_rules rule is refused before the preview")
    func testBulkDisableEmptyingOnlyRulesIsRefused() async throws {
        let result = try await bulk(
            ["force_cast", "explicit_init"],
            enable: false,
            over: "only_rules:\n  - force_cast\n  - explicit_init\n"
        )

        #expect(result.saved == nil)
        #expect(result.viewModel.bulkOperationError?.contains("only_rules") == true)
    }

    enum BulkChange: String, CaseIterable, Sendable {
        case enable, disable, severity
    }

    @Test(
        "Any bulk change to a file SwiftLint already rejects is refused before the preview",
        arguments: BulkChange.allCases
    )
    func testBulkChangeToConflictedFileIsRefused(change: BulkChange) async throws {
        let content = "only_rules:\n  - line_length\n  - force_cast\ndisabled_rules:\n  - explicit_init\n"
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: content)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let viewModel = await MainActor.run {
            let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
            let viewModel = Self.makeViewModel()
            viewModel.selectedRuleIds = ["force_cast"]
            switch change {
            case .enable: viewModel.enableSelectedRules(yamlEngine: yamlEngine)
            case .disable: viewModel.disableSelectedRules(yamlEngine: yamlEngine)
            case .severity: viewModel.setSeverityForSelected(.error, yamlEngine: yamlEngine)
            }
            return viewModel
        }

        #expect(viewModel.bulkDiff == nil)
        #expect(viewModel.bulkOperationError == YAMLConfigError.onlyRulesConflict.localizedDescription)
        #expect(try String(contentsOf: configPath, encoding: .utf8) == content)
    }
}
