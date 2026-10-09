//
//  ConfigurationHealthAnalyzerEnablementTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Which rules the health score counts as enabled. It used to add up its own lists, so a
//  rule enabled in two places counted twice and `only_rules:` was ignored; it now asks
//  `RuleEnablementResolver`, like the rest of the app.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct ConfigurationHealthAnalyzerEnablementTests {
    private func createRule(
        id: String,
        category: RuleCategory = .style,
        isOptIn: Bool = false
    ) -> Rule {
        Rule(id: id, name: id, description: "Test rule", category: category, isOptIn: isOptIn)
    }

    @Test("Rules coverage counts a rule once, however many places enable it")
    func testCoverageCountsEachRuleOnce() {
        let analyzer = ConfigurationHealthAnalyzer()
        var config = YAMLConfigurationEngine.YAMLConfig()
        // A default rule with an explicit entry, and an opt-in rule the catalogue doesn't know
        config.rules["default_rule"] = RuleConfiguration(enabled: true)
        config.optInRules = ["opt_in_0", "unknown_rule"]

        let rules = [createRule(id: "default_rule")]
            + (0..<9).map { createRule(id: "opt_in_\($0)", isOptIn: true) }
        let report = analyzer.analyze(config: config, knownRules: rules)

        // 2 of 10 rules on is 20%, scored against a 50% target
        #expect(report.breakdown.rulesCoverage == 40)
    }

    @Test("only_rules decides which rules count as enabled")
    func testOnlyRulesLimitsCoverageAndBalance() {
        let analyzer = ConfigurationHealthAnalyzer()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.onlyRules = ["style_rule"]

        let rules = [
            createRule(id: "style_rule", category: .style),
            createRule(id: "lint_rule", category: .lint),
            createRule(id: "metrics_rule", category: .metrics),
            createRule(id: "performance_rule", category: .performance)
        ]
        let report = analyzer.analyze(config: config, knownRules: rules)
        let unrestricted = analyzer.analyze(config: YAMLConfigurationEngine.YAMLConfig(), knownRules: rules)

        // 1 of 4 rules on is 25%, scored against a 50% target
        #expect(report.breakdown.rulesCoverage == 50)
        #expect(report.breakdown.categoryBalance < unrestricted.breakdown.categoryBalance)
    }

    @Test("Recommended opt-in rules listed under only_rules count as adopted")
    func testOptInAdoptionWithOnlyRules() {
        let analyzer = ConfigurationHealthAnalyzer()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.onlyRules = ["first_where", "empty_count", "line_length"]
        let report = analyzer.analyze(config: config, knownRules: [])

        #expect(report.breakdown.optInAdoption > 0)
        let optInRecommendation = report.recommendations.first { $0.title == "Enable Recommended Opt-In Rules" }
        #expect(optInRecommendation?.description.contains("first_where") != true)
        #expect(optInRecommendation?.description.contains("empty_count") != true)
    }
}
