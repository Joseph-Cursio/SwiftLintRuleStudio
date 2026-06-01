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
        markdownDocumentation: String? = nil
    ) -> Rule {
        Rule(
            id: ruleId,
            name: ruleId,
            description: "desc",
            category: .style,
            isOptIn: isOptIn,
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
