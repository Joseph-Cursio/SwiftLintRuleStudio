//
//  RuleRegistryEnabledStateTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for RuleRegistry enabled-state resolution (syncEnabledStates / isRuleEnabled),
//  on-demand detail fetching (fetchRuleDetailsIfNeeded), and refreshRules delegation.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct RuleRegistryEnabledStateTests {

    // MARK: - Helpers

    private func makeRule(
        id ruleId: String,
        isOptIn: Bool = false,
        isAnalyzer: Bool = false,
        markdownDocumentation: String? = nil
    ) -> Rule {
        Rule(
            id: ruleId,
            name: ruleId,
            description: "desc",
            category: .style,
            isOptIn: isOptIn,
            isAnalyzer: isAnalyzer,
            markdownDocumentation: markdownDocumentation
        )
    }

    private func makeRegistry(rules: [Rule]) -> RuleRegistry {
        let registry = RuleRegistry(
            swiftLintCLI: MockSwiftLintCLIActor(),
            cacheManager: MockCacheManager()
        )
        registry.setRulesForTesting(rules)
        return registry
    }

    private func enabledMap(_ registry: RuleRegistry) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: registry.rules.map { ($0.id, $0.isEnabled) })
    }

    // MARK: - syncEnabledStates: only_rules

    @Test("only_rules: a rule is enabled iff it appears in only_rules")
    func testOnlyRulesGatesEnabledState() {
        let registry = makeRegistry(rules: [
            makeRule(id: "rule_in"),
            makeRule(id: "rule_out", isOptIn: true)
        ])
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.onlyRules = ["rule_in"]

        registry.syncEnabledStates(with: config)

        let map = enabledMap(registry)
        #expect(map["rule_in"] == true)
        #expect(map["rule_out"] == false)
    }

    // MARK: - syncEnabledStates: opt-in rules

    @Test("opt-in rule listed in opt_in_rules is enabled")
    func testOptInRuleListedIsEnabled() {
        let registry = makeRegistry(rules: [makeRule(id: "opt_rule", isOptIn: true)])
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.optInRules = ["opt_rule"]

        registry.syncEnabledStates(with: config)

        #expect(registry.getRule(id: "opt_rule")?.isEnabled == true)
    }

    @Test("opt-in rule not listed in opt_in_rules is disabled")
    func testOptInRuleNotListedIsDisabled() {
        let registry = makeRegistry(rules: [makeRule(id: "opt_rule", isOptIn: true)])
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.optInRules = ["something_else"]

        registry.syncEnabledStates(with: config)

        #expect(registry.getRule(id: "opt_rule")?.isEnabled == false)
    }

    @Test("opt-in rule with no opt_in_rules section at all is disabled")
    func testOptInRuleWithNoOptInSectionIsDisabled() {
        let registry = makeRegistry(rules: [makeRule(id: "opt_rule", isOptIn: true)])
        let config = YAMLConfigurationEngine.YAMLConfig()

        registry.syncEnabledStates(with: config)

        #expect(registry.getRule(id: "opt_rule")?.isEnabled == false)
    }

    @Test("opt-in rule explicitly disabled via rules dict is disabled even if opt-in-listed")
    func testOptInRuleExplicitlyDisabledWins() {
        let registry = makeRegistry(rules: [makeRule(id: "opt_rule", isOptIn: true)])
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.optInRules = ["opt_rule"]
        config.rules = ["opt_rule": RuleConfiguration(enabled: false)]

        registry.syncEnabledStates(with: config)

        #expect(registry.getRule(id: "opt_rule")?.isEnabled == false)
    }

    // MARK: - syncEnabledStates: analyzer rules

    // Regression: enablement logic lived in three copies — RuleRegistry,
    // RuleAuditView and RuleDetailViewModel — and only the audit copy learned
    // to handle analyzer rules. RuleRegistry therefore fell through to the
    // default `return true`, so the rule browser showed every analyzer rule as
    // enabled even when `analyzer_rules:` did not list it. All three now share
    // RuleEnablementResolver; these tests pin the analyzer contract on the
    // syncEnabledStates path the browser actually uses.

    @Test("analyzer rule absent from analyzer_rules is disabled")
    func testAnalyzerRuleAbsentIsDisabled() {
        let registry = makeRegistry(rules: [
            makeRule(id: "explicit_self", isOptIn: true, isAnalyzer: true)
        ])
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.analyzerRules = ["unused_declaration"]

        registry.syncEnabledStates(with: config)

        #expect(registry.getRule(id: "explicit_self")?.isEnabled == false)
    }

    @Test("analyzer rule with no analyzer_rules section at all is disabled")
    func testAnalyzerRuleWithNoAnalyzerSectionIsDisabled() {
        let registry = makeRegistry(rules: [
            makeRule(id: "explicit_self", isOptIn: true, isAnalyzer: true)
        ])
        let config = YAMLConfigurationEngine.YAMLConfig()

        registry.syncEnabledStates(with: config)

        #expect(registry.getRule(id: "explicit_self")?.isEnabled == false)
    }

    @Test("analyzer rule not reported as opt-in still requires analyzer_rules")
    func testAnalyzerRuleNotOptInStillRequiresAnalyzerList() {
        // The sharpest form of the pre-fix bug. SwiftLint reports most analyzer
        // rules as opt-in, and the old opt-in branch happened to return false
        // for them — masking the defect. An analyzer rule *not* flagged opt-in
        // fell through every branch to the default `return true`, so the
        // browser showed it enabled while SwiftLint would never run it.
        let registry = makeRegistry(rules: [
            makeRule(id: "unused_declaration", isOptIn: false, isAnalyzer: true)
        ])
        let config = YAMLConfigurationEngine.YAMLConfig()

        registry.syncEnabledStates(with: config)

        #expect(registry.getRule(id: "unused_declaration")?.isEnabled == false)
    }

    @Test("analyzer rule listed in analyzer_rules is enabled")
    func testAnalyzerRuleListedIsEnabled() {
        let registry = makeRegistry(rules: [
            makeRule(id: "explicit_self", isOptIn: true, isAnalyzer: true)
        ])
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.analyzerRules = ["explicit_self"]

        registry.syncEnabledStates(with: config)

        #expect(registry.getRule(id: "explicit_self")?.isEnabled == true)
    }

    @Test("analyzer rule listed only in opt_in_rules stays disabled")
    func testAnalyzerRuleNotEnabledByOptInRulesList() {
        // SwiftLint honors analyzer rules only via `analyzer_rules:`, and it
        // also reports them as opt-in — so the analyzer branch has to be
        // checked before the opt-in branch or a stray entry would enable them.
        let registry = makeRegistry(rules: [
            makeRule(id: "explicit_self", isOptIn: true, isAnalyzer: true)
        ])
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.optInRules = ["explicit_self"]

        registry.syncEnabledStates(with: config)

        #expect(registry.getRule(id: "explicit_self")?.isEnabled == false)
    }

    @Test("analyzer rule explicitly disabled via rules dict wins over analyzer_rules")
    func testAnalyzerRuleExplicitlyDisabledWins() {
        let registry = makeRegistry(rules: [
            makeRule(id: "explicit_self", isOptIn: true, isAnalyzer: true)
        ])
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.analyzerRules = ["explicit_self"]
        config.rules = ["explicit_self": RuleConfiguration(enabled: false)]

        registry.syncEnabledStates(with: config)

        #expect(registry.getRule(id: "explicit_self")?.isEnabled == false)
    }

    @Test("only_rules outranks analyzer_rules")
    func testOnlyRulesOutranksAnalyzerRules() {
        let registry = makeRegistry(rules: [
            makeRule(id: "explicit_self", isOptIn: true, isAnalyzer: true),
            makeRule(id: "force_cast")
        ])
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.onlyRules = ["force_cast"]
        config.analyzerRules = ["explicit_self"]

        registry.syncEnabledStates(with: config)

        let map = enabledMap(registry)
        #expect(map["explicit_self"] == false)
        #expect(map["force_cast"] == true)
    }

    // MARK: - syncEnabledStates: default (non-opt-in) rules

    @Test("default rule with no config is enabled")
    func testDefaultRuleEnabledByDefault() {
        let registry = makeRegistry(rules: [makeRule(id: "default_rule")])
        let config = YAMLConfigurationEngine.YAMLConfig()

        registry.syncEnabledStates(with: config)

        #expect(registry.getRule(id: "default_rule")?.isEnabled == true)
    }

    @Test("default rule listed in disabled_rules is disabled")
    func testDefaultRuleInDisabledRulesIsDisabled() {
        let registry = makeRegistry(rules: [makeRule(id: "default_rule")])
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["default_rule"]

        registry.syncEnabledStates(with: config)

        #expect(registry.getRule(id: "default_rule")?.isEnabled == false)
    }

    @Test("default rule with explicit rules-dict entry honors that entry's enabled flag")
    func testDefaultRuleHonorsExplicitRuleConfig() {
        let registry = makeRegistry(rules: [
            makeRule(id: "on_rule"),
            makeRule(id: "off_rule")
        ])
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules = [
            "on_rule": RuleConfiguration(enabled: true),
            "off_rule": RuleConfiguration(enabled: false)
        ]

        registry.syncEnabledStates(with: config)

        let map = enabledMap(registry)
        #expect(map["on_rule"] == true)
        #expect(map["off_rule"] == false)
    }

    // MARK: - fetchRuleDetailsIfNeeded

    @Test("fetchRuleDetailsIfNeeded enriches a rule that has no documentation")
    func testFetchRuleDetailsIfNeededEnrichesRule() async {
        let registry = makeRegistry(rules: [makeRule(id: "force_cast")])

        await registry.fetchRuleDetailsIfNeeded(id: "force_cast")

        let enriched = registry.getRule(id: "force_cast")
        #expect(enriched?.markdownDocumentation?.isEmpty == false)
    }

    @Test("fetchRuleDetailsIfNeeded is a no-op when the rule already has documentation")
    func testFetchRuleDetailsIfNeededSkipsRuleWithDocs() async {
        let registry = makeRegistry(rules: [
            makeRule(id: "force_cast", markdownDocumentation: "existing docs")
        ])

        await registry.fetchRuleDetailsIfNeeded(id: "force_cast")

        #expect(registry.getRule(id: "force_cast")?.markdownDocumentation == "existing docs")
    }

    @Test("fetchRuleDetailsIfNeeded is a no-op for an unknown rule id")
    func testFetchRuleDetailsIfNeededUnknownRuleNoOp() async {
        let registry = makeRegistry(rules: [makeRule(id: "force_cast")])

        await registry.fetchRuleDetailsIfNeeded(id: "does_not_exist")

        // The existing rule is untouched and no rule was added.
        #expect(registry.rules.count == 1)
        #expect(registry.getRule(id: "force_cast")?.markdownDocumentation == nil)
    }

    @Test("fetchRuleDetailsIfNeeded leaves the rule unchanged when detail fetch fails")
    func testFetchRuleDetailsIfNeededFetchFailureLeavesRule() async {
        let registry = RuleRegistry(
            swiftLintCLI: MockSwiftLintCLIActor(shouldFail: true),
            cacheManager: MockCacheManager()
        )
        registry.setRulesForTesting([makeRule(id: "force_cast")])

        await registry.fetchRuleDetailsIfNeeded(id: "force_cast")

        #expect(registry.getRule(id: "force_cast")?.markdownDocumentation == nil)
    }

    // MARK: - refreshRules / isRunningTests

    @Test("refreshRules loads rules from the cache when SwiftLint fails")
    func testRefreshRulesPopulatesFromCache() async throws {
        let cache = MockCacheManager()
        cache.cachedRules = [makeRule(id: "cached_rule")]
        let registry = RuleRegistry(
            swiftLintCLI: MockSwiftLintCLIActor(shouldFail: true),
            cacheManager: cache
        )

        try await registry.refreshRules()

        #expect(registry.getRule(id: "cached_rule") != nil)
    }

    @Test("isRunningTests reflects the XCTestConfigurationFilePath environment flag")
    func testIsRunningTestsReflectsEnvironment() {
        let expected = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #expect(RuleRegistry.isRunningTests == expected)
    }
}
