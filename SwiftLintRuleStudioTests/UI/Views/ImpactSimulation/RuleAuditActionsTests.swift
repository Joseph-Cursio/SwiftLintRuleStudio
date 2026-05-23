//
//  RuleAuditActionsTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for RuleAuditView.applyEnableRules and support types
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
@Suite("RuleAuditView.applyEnableRules Tests")
struct RuleAuditActionsTests {

    // MARK: - Basic Enable

    @Test("Enabling a rule adds it to config.rules with enabled=true")
    func enablesRuleInConfig() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        let optInRuleIds: Set<String> = []

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["force_cast"],
            optInRuleIds: optInRuleIds
        )

        #expect(config.rules["force_cast"]?.enabled == true)
    }

    @Test("Enabling a rule that already exists sets enabled to true")
    func enablesExistingDisabledRule() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules["force_cast"] = RuleConfiguration(enabled: false)

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["force_cast"],
            optInRuleIds: []
        )

        #expect(config.rules["force_cast"]?.enabled == true)
    }

    @Test("Enabling multiple rules adds all of them")
    func enablesMultipleRules() {
        var config = YAMLConfigurationEngine.YAMLConfig()

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["rule_one", "rule_two", "rule_three"],
            optInRuleIds: []
        )

        #expect(config.rules["rule_one"]?.enabled == true)
        #expect(config.rules["rule_two"]?.enabled == true)
        #expect(config.rules["rule_three"]?.enabled == true)
    }

    // MARK: - Disabled Rules Removal

    @Test("Enabling a rule removes it from disabledRules list")
    func removesFromDisabledRules() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["force_cast", "line_length"]

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["force_cast"],
            optInRuleIds: []
        )

        #expect(config.disabledRules?.contains("force_cast") == false)
        #expect(config.disabledRules?.contains("line_length") == true)
    }

    @Test("Removing last disabled rule sets disabledRules to nil")
    func setsDisabledRulesToNilWhenEmpty() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["force_cast"]

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["force_cast"],
            optInRuleIds: []
        )

        #expect(config.disabledRules == nil)
    }

    @Test("Enabling rule not in disabledRules does not affect disabledRules")
    func doesNotAffectUnrelatedDisabledRules() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["line_length"]

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["force_cast"],
            optInRuleIds: []
        )

        #expect(config.disabledRules == ["line_length"])
    }

    // MARK: - Opt-In Rules

    @Test("Enabling an opt-in rule adds it to optInRules")
    func addsToOptInRules() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        let optInRuleIds: Set<String> = ["explicit_init"]

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["explicit_init"],
            optInRuleIds: optInRuleIds
        )

        #expect(config.optInRules?.contains("explicit_init") == true)
    }

    @Test("Enabling an opt-in rule that is already in optInRules does not duplicate")
    func doesNotDuplicateOptInRule() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.optInRules = ["explicit_init"]
        let optInRuleIds: Set<String> = ["explicit_init"]

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["explicit_init"],
            optInRuleIds: optInRuleIds
        )

        let occurrences = config.optInRules?.filter { $0 == "explicit_init" }.count ?? 0
        #expect(occurrences == 1)
    }

    @Test("Enabling a non-opt-in rule does not add to optInRules")
    func doesNotAddNonOptInToOptInRules() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        let optInRuleIds: Set<String> = ["explicit_init"]

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["force_cast"],
            optInRuleIds: optInRuleIds
        )

        #expect(config.optInRules == nil)
    }

    // MARK: - Only Rules

    @Test("Enabling a rule with existing onlyRules adds it to onlyRules")
    func addsToOnlyRules() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.onlyRules = ["existing_rule"]

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["new_rule"],
            optInRuleIds: []
        )

        #expect(config.onlyRules?.contains("new_rule") == true)
        #expect(config.onlyRules?.contains("existing_rule") == true)
    }

    @Test("Enabling a rule already in onlyRules does not duplicate")
    func doesNotDuplicateOnlyRule() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.onlyRules = ["force_cast"]

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["force_cast"],
            optInRuleIds: []
        )

        let occurrences = config.onlyRules?.filter { $0 == "force_cast" }.count ?? 0
        #expect(occurrences == 1)
    }

    @Test("Nil onlyRules is not affected")
    func nilOnlyRulesUnaffected() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        // config.onlyRules is nil by default

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["force_cast"],
            optInRuleIds: []
        )

        #expect(config.onlyRules == nil)
    }

    // MARK: - Empty Input

    @Test("Enabling empty ruleIds array does not change config")
    func emptyRuleIds() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["force_cast"]

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: [],
            optInRuleIds: []
        )

        #expect(config.disabledRules == ["force_cast"])
        #expect(config.rules.isEmpty)
    }

    // MARK: - Combined Scenarios

    // MARK: - Analyzer Rules

    @Test("Enabling an analyzer rule adds it to analyzerRules, not optInRules")
    func addsToAnalyzerRules() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        let analyzerRuleIds: Set<String> = ["unused_declaration"]
        let optInRuleIds: Set<String> = []

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["unused_declaration"],
            optInRuleIds: optInRuleIds,
            analyzerRuleIds: analyzerRuleIds
        )

        #expect(config.analyzerRules?.contains("unused_declaration") == true)
        #expect(config.optInRules?.contains("unused_declaration") != true)
    }

    @Test("Enabling an analyzer rule already in analyzerRules does not duplicate")
    func doesNotDuplicateAnalyzerRule() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.analyzerRules = ["unused_declaration"]
        let analyzerRuleIds: Set<String> = ["unused_declaration"]

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["unused_declaration"],
            optInRuleIds: [],
            analyzerRuleIds: analyzerRuleIds
        )

        let occurrences = config.analyzerRules?.filter { $0 == "unused_declaration" }.count ?? 0
        #expect(occurrences == 1)
    }

    @Test("Analyzer routing wins when a rule appears in both analyzer and opt-in sets")
    func analyzerRoutingTakesPrecedenceOverOptIn() {
        // Defensive — production never populates both for the same id, but
        // the routing logic uses `else if` and should not double-list a rule.
        var config = YAMLConfigurationEngine.YAMLConfig()
        let bothIds: Set<String> = ["unused_declaration"]

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["unused_declaration"],
            optInRuleIds: bothIds,
            analyzerRuleIds: bothIds
        )

        #expect(config.analyzerRules?.contains("unused_declaration") == true)
        #expect(config.optInRules?.contains("unused_declaration") != true)
    }

    @Test("Enabling mix of analyzer, opt-in, and default routes each to the right list")
    func mixedRulesGoToCorrectLists() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        let optInRuleIds: Set<String> = ["explicit_init"]
        let analyzerRuleIds: Set<String> = ["unused_declaration"]

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["force_cast", "explicit_init", "unused_declaration"],
            optInRuleIds: optInRuleIds,
            analyzerRuleIds: analyzerRuleIds
        )

        #expect(config.analyzerRules == ["unused_declaration"])
        #expect(config.optInRules == ["explicit_init"])
        #expect(config.rules["force_cast"]?.enabled == true)
        #expect(config.rules["explicit_init"]?.enabled == true)
        #expect(config.rules["unused_declaration"]?.enabled == true)
    }

    @Test("Enabling opt-in rule removes from disabled, adds to optIn, and adds to onlyRules")
    func combinedScenario() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["explicit_init", "line_length"]
        config.onlyRules = ["force_cast"]
        let optInRuleIds: Set<String> = ["explicit_init"]

        RuleAuditView.applyEnableRules(
            config: &config,
            ruleIds: ["explicit_init"],
            optInRuleIds: optInRuleIds
        )

        // Should be enabled in rules
        #expect(config.rules["explicit_init"]?.enabled == true)
        // Should be removed from disabled_rules
        #expect(config.disabledRules?.contains("explicit_init") == false)
        #expect(config.disabledRules?.contains("line_length") == true)
        // Should be added to opt_in_rules
        #expect(config.optInRules?.contains("explicit_init") == true)
        // Should be added to only_rules
        #expect(config.onlyRules?.contains("explicit_init") == true)
        #expect(config.onlyRules?.contains("force_cast") == true)
    }
}
