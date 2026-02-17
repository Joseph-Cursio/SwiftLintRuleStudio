//
//  MigrationAssistantTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for MigrationAssistant
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

@MainActor
struct MigrationAssistantTests {

    private let assistant = MigrationAssistant()

    // MARK: - Helpers

    private func makeConfig(
        rules: [String: RuleConfiguration] = [:],
        disabledRules: [String]? = nil,
        optInRules: [String]? = nil
    ) -> YAMLConfigurationEngine.YAMLConfig {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules = rules
        config.disabledRules = disabledRules
        config.optInRules = optInRules
        return config
    }

    // MARK: - Migration Detection

    @Test("Detects renamed rules in migration")
    func testDetectsRenamedRules() {
        let config = makeConfig(rules: ["variable_name": RuleConfiguration(enabled: true)])
        let plan = assistant.detectMigrations(config: config, fromVersion: "0.20.0", toVersion: "0.55.0")

        let renameSteps = plan.steps.filter {
            if case .renameRule(let from, _) = $0, from == "variable_name" { return true }
            return false
        }
        #expect(!renameSteps.isEmpty)
    }

    @Test("No migrations for clean config")
    func testNoMigrationsForCleanConfig() {
        let config = makeConfig(rules: [
            "line_length": RuleConfiguration(enabled: true),
            "force_cast": RuleConfiguration(enabled: true)
        ])
        let plan = assistant.detectMigrations(config: config, fromVersion: "0.50.0", toVersion: "0.55.0")

        // Should only have manual action for new rules (if any)
        let actionSteps = plan.steps.filter(\.canAutoApply)
        #expect(actionSteps.isEmpty)
    }

    @Test("Detects new rules available")
    func testDetectsNewRules() {
        let config = makeConfig(rules: ["force_cast": RuleConfiguration(enabled: true)])
        let plan = assistant.detectMigrations(config: config, fromVersion: "0.24.0", toVersion: "0.25.0")

        let manualSteps = plan.manualSteps
        let hasNewRulesStep = manualSteps.contains { step in
            if case .manualAction(let desc) = step { return desc.contains("New rules") }
            return false
        }
        #expect(hasNewRulesStep)
    }

    // MARK: - Migration Application

    @Test("Applies rename migration to rules dict")
    func testAppliesRenameToRulesDict() {
        var config = makeConfig(rules: ["variable_name": RuleConfiguration(enabled: true)])
        let plan = MigrationPlan(
            fromVersion: "0.20.0",
            toVersion: "0.30.0",
            steps: [.renameRule(from: "variable_name", to: "identifier_name")]
        )

        assistant.applyMigration(plan, to: &config)
        #expect(config.rules["identifier_name"] != nil)
        #expect(config.rules["variable_name"] == nil)
    }

    @Test("Applies rename to disabled_rules list")
    func testAppliesRenameToDisabledRules() {
        var config = makeConfig(disabledRules: ["variable_name", "line_length"])
        let plan = MigrationPlan(
            fromVersion: "0.20.0",
            toVersion: "0.30.0",
            steps: [.renameRule(from: "variable_name", to: "identifier_name")]
        )

        assistant.applyMigration(plan, to: &config)
        #expect(config.disabledRules?.contains("identifier_name") == true)
        #expect(config.disabledRules?.contains("variable_name") == false)
        #expect(config.disabledRules?.contains("line_length") == true)
    }

    @Test("Applies remove migration")
    func testAppliesRemoveMigration() {
        var config = makeConfig(rules: ["old_rule": RuleConfiguration(enabled: true)])
        let plan = MigrationPlan(
            fromVersion: "0.20.0",
            toVersion: "0.30.0",
            steps: [.removeDeprecatedRule(ruleId: "old_rule", reason: "No longer needed")]
        )

        assistant.applyMigration(plan, to: &config)
        #expect(config.rules["old_rule"] == nil)
    }

    @Test("Skips manual action steps during apply")
    func testSkipsManualSteps() {
        var config = makeConfig(rules: ["force_cast": RuleConfiguration(enabled: true)])
        let plan = MigrationPlan(
            fromVersion: "0.20.0",
            toVersion: "0.30.0",
            steps: [.manualAction(description: "Review new rules")]
        )

        assistant.applyMigration(plan, to: &config)
        // Config should be unchanged
        #expect(config.rules["force_cast"] != nil)
    }

    @Test("canAutoApply is true when all steps are auto-applicable")
    func testCanAutoApply() {
        let plan = MigrationPlan(
            fromVersion: "0.20.0",
            toVersion: "0.30.0",
            steps: [
                .renameRule(from: "a", to: "b"),
                .removeDeprecatedRule(ruleId: "c", reason: "removed")
            ]
        )
        #expect(plan.canAutoApply)
    }

    @Test("canAutoApply is false when manual steps exist")
    func testCanAutoApplyFalseWithManual() {
        let plan = MigrationPlan(
            fromVersion: "0.20.0",
            toVersion: "0.30.0",
            steps: [
                .renameRule(from: "a", to: "b"),
                .manualAction(description: "Do something")
            ]
        )
        #expect(!plan.canAutoApply)
    }

    @Test("Applies parameter update migration")
    func testAppliesParameterUpdate() {
        var config = makeConfig(rules: [
            "test_rule": RuleConfiguration(
                enabled: true,
                parameters: ["old_param": AnyCodable(100)]
            )
        ])
        let plan = MigrationPlan(
            fromVersion: "0.20.0",
            toVersion: "0.30.0",
            steps: [.updateParameter(ruleId: "test_rule", oldParam: "old_param", newParam: "new_param")]
        )

        assistant.applyMigration(plan, to: &config)
        #expect(config.rules["test_rule"]?.parameters?["new_param"] != nil)
        #expect(config.rules["test_rule"]?.parameters?["old_param"] == nil)
    }
}
