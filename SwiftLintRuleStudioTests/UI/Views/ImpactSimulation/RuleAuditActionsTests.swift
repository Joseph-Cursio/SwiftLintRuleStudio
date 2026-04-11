//
//  RuleAuditActionsTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for RuleAuditView.applyEnableRules and support types
//

import Testing
import Foundation
@testable import SwiftLintRuleStudioCore
@testable import SwiftLintRuleStudio

@MainActor
@Suite("RuleAuditView.applyEnableRules Tests")
struct RuleAuditApplyEnableRulesTests {

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
