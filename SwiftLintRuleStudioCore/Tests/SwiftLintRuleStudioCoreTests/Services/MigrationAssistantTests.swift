//
//  MigrationAssistantTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for MigrationAssistant
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

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
        #expect(renameSteps.isEmpty == false)
    }

    /// Both rules still exist in 0.65.0, next to the rules the table once renamed them to.
    /// `multiple_closures_with_trailing_closure` is on by default and `trailing_closure` is
    /// opt-in, so the rename changed what the config linted.
    @Test("Does not rename a rule that still exists", arguments: [
        "multiple_closures_with_trailing_closure", "generic_type_name"
    ])
    func testDoesNotRenameLiveRule(ruleId: String) {
        let config = makeConfig(rules: [ruleId: RuleConfiguration(enabled: true)])
        let plan = assistant.detectMigrations(config: config, fromVersion: "0.20.0", toVersion: "0.65.0")
        #expect(plan.autoApplyableSteps.isEmpty)
    }

    /// Deprecated in 0.51.0 in favor of the Swift compiler warning and removed in 0.58.0.
    /// No rule replaced them: `unused_closure_use` never existed, and `no_empty_block` is
    /// an unrelated opt-in rule.
    @Test("Removes a rule the compiler replaced rather than renaming it", arguments: [
        "unused_capture_list", "inert_defer"
    ])
    func testRemovesCompilerReplacedRule(ruleId: String) {
        let config = makeConfig(optInRules: [ruleId])
        let plan = assistant.detectMigrations(config: config, fromVersion: "0.50.0", toVersion: "0.65.0")
        #expect(plan.autoApplyableSteps.map(\.id) == ["remove-\(ruleId)"])
    }

    /// Removed in 0.59.1 for too many false positives, one release after it shipped.
    @Test("Removes opaque_over_existential when the range crosses 0.59.1")
    func testRemovesOpaqueOverExistential() {
        let config = makeConfig(optInRules: ["opaque_over_existential"])
        let plan = assistant.detectMigrations(config: config, fromVersion: "0.59.0", toVersion: "0.60.0")
        #expect(plan.autoApplyableSteps.map(\.id) == ["remove-opaque_over_existential"])
    }

    /// Removed in 0.7.0, when their limits became `variable_name`'s (now `identifier_name`'s)
    /// `min_length` and `max_length`. Renaming would move a bare threshold onto
    /// `identifier_name`, overwriting any configuration it already has.
    @Test("Removes a merged rule rather than renaming it onto identifier_name", arguments: [
        "variable_name_max_length", "variable_name_min_length"
    ])
    func testRemovesMergedRule(ruleId: String) {
        let config = makeConfig(rules: [
            ruleId: RuleConfiguration(enabled: true),
            "identifier_name": RuleConfiguration(enabled: true, severity: .error)
        ])
        let plan = assistant.detectMigrations(config: config, fromVersion: "0.6.0", toVersion: "0.65.0")
        #expect(plan.autoApplyableSteps.map(\.id) == ["remove-\(ruleId)"])
    }

    /// `if_let_shadowing` shipped only in 0.50.0-rc.1; 0.50.0 calls it `shorthand_optional_binding`.
    @Test("Renames if_let_shadowing once the target version has shorthand_optional_binding", arguments: [
        ("0.49.0", false), ("0.50.0", true), ("0.65.0", true)
    ])
    func testIfLetShadowingRename(toVersion: String, renames: Bool) {
        let config = makeConfig(optInRules: ["if_let_shadowing"])
        let plan = assistant.detectMigrations(config: config, fromVersion: "0.40.0", toVersion: toVersion)
        let rename = MigrationStep.renameRule(from: "if_let_shadowing", newName: "shorthand_optional_binding")
        #expect(plan.steps.contains(rename) == renames)
    }

    @Test("A SwiftLint alias is renamed in every rule list")
    func testAliasRenamedInEveryList() {
        var config = makeConfig(disabledRules: ["redundant_self_in_closure"], optInRules: ["if_let_shadowing"])
        config.onlyRules = ["if_let_shadowing", "operator_whitespace"]
        config.analyzerRules = ["redundant_optional_initialization"]
        let plan = assistant.detectMigrations(config: config, fromVersion: "0.49.0", toVersion: "0.65.0")
        assistant.applyMigration(plan, to: &config)
        #expect(config.disabledRules == ["redundant_self"])
        #expect(config.optInRules == ["shorthand_optional_binding"])
        #expect(config.onlyRules == ["shorthand_optional_binding", "function_name_whitespace"])
        #expect(config.analyzerRules == ["implicit_optional_initialization"])
    }

    @Test("A rename keeps the configuration the new id already has")
    func testRenameKeepsExistingTargetConfiguration() {
        var config = makeConfig(rules: [
            "variable_name": RuleConfiguration(enabled: true, severity: .error),
            "identifier_name": RuleConfiguration(enabled: true, severity: .warning)
        ])
        let plan = assistant.detectMigrations(config: config, fromVersion: "0.16.0", toVersion: "0.65.0")
        assistant.applyMigration(plan, to: &config)
        #expect(config.rules == ["identifier_name": RuleConfiguration(enabled: true, severity: .warning)])
    }

    @Test("The new-rules note leaves out a rule the config uses, under its own name or an old one")
    func testNewRulesNoteExcludesRulesInUse() throws {
        let config = makeConfig(optInRules: ["redundant_optional_initialization", "prefer_condition_list"])
        let plan = assistant.detectMigrations(config: config, fromVersion: "0.59.0", toVersion: "0.60.0")
        // Both 0.60.0 additions are in use, so there is nothing new to suggest.
        #expect(plan.manualSteps.isEmpty)
        let rename = MigrationStep.renameRule(
            from: "redundant_optional_initialization", newName: "implicit_optional_initialization"
        )
        #expect(plan.steps == [rename])
    }

    /// A version typed with a leading `v` once compared below every release.
    @Test("Versions with a leading v plan like plain ones")
    func testLeadingVVersions() {
        let config = makeConfig(optInRules: ["inert_defer"])
        let typed = assistant.detectMigrations(config: config, fromVersion: "v0.50.0", toVersion: "v0.65.0")
        let plain = assistant.detectMigrations(config: config, fromVersion: "0.50.0", toVersion: "0.65.0")
        #expect(typed.steps == plain.steps)
        #expect(typed.steps.contains(.removeDeprecatedRule(
            ruleId: "inert_defer", reason: SwiftLintDeprecations.removedRules["inert_defer"]?.message ?? ""
        )))
    }

    /// 0.50.0-rc.1 still registers `if_let_shadowing`; renaming it there would turn the rule off.
    @Test("A migration to a pre-release does not apply a rename its release brings")
    func testPreReleaseTargetKeepsOldName() {
        let config = makeConfig(optInRules: ["if_let_shadowing"])
        let toRC = assistant.detectMigrations(config: config, fromVersion: "0.49.0", toVersion: "0.50.0-rc.1")
        #expect(toRC.autoApplyableSteps.isEmpty)
        let toRelease = assistant.detectMigrations(config: config, fromVersion: "0.49.0", toVersion: "0.50.0")
        #expect(toRelease.steps.contains(.renameRule(from: "if_let_shadowing", newName: "shorthand_optional_binding")))
    }

    /// `rule: error` is a severity shorthand the engine holds as a passthrough node, not in `rules`.
    @Test("Severity-shorthand rules are renamed and removed like any other")
    func testSeverityShorthandRules() throws {
        var config = try YAMLConfigurationEngine.parse("""
            redundant_self_in_closure: error
            inert_defer: warning

            """)
        let plan = assistant.detectMigrations(config: config, fromVersion: "0.57.0", toVersion: "0.65.0")
        #expect(plan.autoApplyableSteps.map(\.id).sorted() == [
            "remove-inert_defer", "rename-redundant_self_in_closure-redundant_self"
        ])
        assistant.applyMigration(plan, to: &config)
        let yaml = try YAMLConfigurationEngine.serialize(config)
        #expect(yaml.contains("redundant_self: error"))
        #expect(yaml.contains("redundant_self_in_closure") == false)
        #expect(yaml.contains("inert_defer") == false)
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
        let plan = assistant.detectMigrations(config: config, fromVersion: "0.55.0", toVersion: "0.56.0")

        let manualSteps = plan.manualSteps
        let hasNewRulesStep = manualSteps.contains { step in
            if case .manualAction(let desc) = step { return desc.contains("New rules") }
            return false
        }
        #expect(hasNewRulesStep)
    }

    /// `anyobject_protocol` was added in 0.27.0, deprecated with no replacement in 0.50.0, and
    /// removed in 0.57.0. A deprecated rule is on its way out, so it isn't offered either.
    @Test("New-rules note leaves out a rule the target version retired", arguments: [
        ("0.49.0", true), ("0.50.0", false), ("0.56.0", false), ("0.57.0", false), ("0.65.0", false)
    ])
    func testNewRulesNoteSkipsRemovedRule(toVersion: String, listed: Bool) throws {
        let plan = assistant.detectMigrations(config: makeConfig(), fromVersion: "0.20.0", toVersion: toVersion)
        let note = try #require(plan.manualSteps.first)
        #expect(note.description.contains("anyobject_protocol") == listed)
    }

    // MARK: - Migration Application

    @Test("Applies rename migration to rules dict")
    func testAppliesRenameToRulesDict() {
        var config = makeConfig(rules: ["variable_name": RuleConfiguration(enabled: true)])
        let plan = MigrationPlan(
            fromVersion: "0.20.0",
            toVersion: "0.30.0",
            steps: [.renameRule(from: "variable_name", newName: "identifier_name")]
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
            steps: [.renameRule(from: "variable_name", newName: "identifier_name")]
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
                .renameRule(from: "a", newName: "b"),
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
                .renameRule(from: "a", newName: "b"),
                .manualAction(description: "Do something")
            ]
        )
        #expect(plan.canAutoApply == false)
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
