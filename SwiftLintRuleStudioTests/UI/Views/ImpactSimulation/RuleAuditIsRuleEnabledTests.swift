//
//  RuleAuditIsRuleEnabledTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for RuleAuditView.isRuleEnabled — analyzer/opt-in/disabled routing.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
@Suite("RuleAuditView.isRuleEnabled Tests")
struct RuleAuditIsRuleEnabledTests {

    private func makeRule(id: String, isOptIn: Bool, isAnalyzer: Bool) -> Rule {
        Rule(
            id: id,
            name: id,
            description: "",
            category: .lint,
            isOptIn: isOptIn,
            isAnalyzer: isAnalyzer
        )
    }

    @Test("Analyzer rule listed under analyzer_rules is reported as enabled")
    func analyzerRuleInAnalyzerRulesIsEnabled() {
        // Regression: SwiftLint reports analyzer rules like `explicit_self` as
        // opt-in: yes. Pre-fix, isRuleEnabled only checked `optInRules` and so
        // misclassified analyzer rules — already listed under `analyzer_rules:`
        // — as disabled. Every audit then offered to re-enable them.
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.analyzerRules = ["explicit_self"]

        let rule = makeRule(id: "explicit_self", isOptIn: true, isAnalyzer: true)

        #expect(RuleAuditView.isRuleEnabled(rule, config: config) == true)
    }

    @Test("Analyzer rule absent from analyzer_rules is reported as disabled")
    func analyzerRuleAbsentIsDisabled() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.analyzerRules = ["unused_declaration"]

        let rule = makeRule(id: "explicit_self", isOptIn: true, isAnalyzer: true)

        #expect(RuleAuditView.isRuleEnabled(rule, config: config) == false)
    }

    @Test("Analyzer rule with rules entry enabled=false is reported as disabled")
    func analyzerRuleExplicitlyDisabledOverridesAnalyzerList() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.analyzerRules = ["explicit_self"]
        config.rules["explicit_self"] = RuleConfiguration(enabled: false)

        let rule = makeRule(id: "explicit_self", isOptIn: true, isAnalyzer: true)

        #expect(RuleAuditView.isRuleEnabled(rule, config: config) == false)
    }

    @Test("Analyzer rule presence in opt_in_rules does not enable it")
    func analyzerRuleNotEnabledByOptInRulesList() {
        // SwiftLint only honors analyzer rules in `analyzer_rules:`. Make sure
        // we mirror that — a stray entry under `opt_in_rules:` should not count.
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.optInRules = ["explicit_self"]

        let rule = makeRule(id: "explicit_self", isOptIn: true, isAnalyzer: true)

        #expect(RuleAuditView.isRuleEnabled(rule, config: config) == false)
    }

    @Test("Opt-in (non-analyzer) rule listed in opt_in_rules is enabled")
    func optInRuleInOptInRulesIsEnabled() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.optInRules = ["explicit_init"]

        let rule = makeRule(id: "explicit_init", isOptIn: true, isAnalyzer: false)

        #expect(RuleAuditView.isRuleEnabled(rule, config: config) == true)
    }

    @Test("Default rule absent from disabled_rules is enabled")
    func defaultRuleEnabledWhenNotDisabled() {
        let config = YAMLConfigurationEngine.YAMLConfig()
        let rule = makeRule(id: "force_cast", isOptIn: false, isAnalyzer: false)

        #expect(RuleAuditView.isRuleEnabled(rule, config: config) == true)
    }

    @Test("Default rule listed in disabled_rules is disabled")
    func defaultRuleDisabledByDisabledRules() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["force_cast"]

        let rule = makeRule(id: "force_cast", isOptIn: false, isAnalyzer: false)

        #expect(RuleAuditView.isRuleEnabled(rule, config: config) == false)
    }

    @Test("only_rules acts as an allowlist regardless of analyzer/opt-in")
    func onlyRulesActsAsAllowlist() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.onlyRules = ["force_cast"]
        config.analyzerRules = ["explicit_self"]

        let analyzerRule = makeRule(id: "explicit_self", isOptIn: true, isAnalyzer: true)
        let allowedRule = makeRule(id: "force_cast", isOptIn: false, isAnalyzer: false)

        #expect(RuleAuditView.isRuleEnabled(analyzerRule, config: config) == false)
        #expect(RuleAuditView.isRuleEnabled(allowedRule, config: config) == true)
    }
}
