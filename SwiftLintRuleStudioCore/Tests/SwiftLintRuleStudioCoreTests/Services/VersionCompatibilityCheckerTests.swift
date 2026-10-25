//
//  VersionCompatibilityCheckerTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for VersionCompatibilityChecker
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct VersionCompatibilityCheckerTests {

    private let checker = VersionCompatibilityChecker()

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

    // MARK: - Deprecated Rules

    @Test("Detects deprecated rules in config")
    func testDetectsDeprecatedRules() throws {
        let config = makeConfig(rules: ["unused_capture_list": RuleConfiguration(enabled: true)])
        // Deprecated in 0.51.0 in favor of the Swift compiler warning, removed in 0.58.0
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.55.0")
        let deprecated = try #require(report.deprecatedRules.first)
        #expect(deprecated.ruleId == "unused_capture_list")
        #expect(deprecated.replacement == nil)
        #expect(report.renamedRules.isEmpty)
    }

    @Test("No deprecated rules for clean config")
    func testNoDeprecatedForCleanConfig() {
        let config = makeConfig(rules: [
            "line_length": RuleConfiguration(enabled: true),
            "force_cast": RuleConfiguration(enabled: true)
        ])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.55.0")
        #expect(report.deprecatedRules.isEmpty)
    }

    // MARK: - Removed Rules

    @Test("Detects removed rules in config")
    func testDetectsRemovedRules() throws {
        let config = makeConfig(rules: ["anyobject_protocol": RuleConfiguration(enabled: true)])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.60.0")
        let removedRule = try #require(report.removedRules.first)
        #expect(removedRule.ruleId == "anyobject_protocol")
    }

    /// SwiftLint deprecated `anyobject_protocol` in 0.50.0, once the compiler handled its
    /// check, and removed it in 0.57.0.
    @Test("Reports anyobject_protocol as deprecated before its removal")
    func testAnyObjectProtocolIsDeprecatedFirst() throws {
        let config = makeConfig(optInRules: ["anyobject_protocol"])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.55.0")
        #expect(report.removedRules.isEmpty)
        let deprecated = try #require(report.deprecatedRules.first)
        #expect(deprecated.ruleId == "anyobject_protocol")
        #expect(deprecated.deprecatedInVersion == "0.50.0")
        #expect(deprecated.replacement == nil)
    }

    /// `opaque_over_existential` shipped only in 0.59.0.
    @Test("Reports opaque_over_existential as removed in 0.59.1")
    func testOpaqueOverExistentialIsRemoved() throws {
        let config = makeConfig(optInRules: ["opaque_over_existential"])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.65.0")
        let removed = try #require(report.removedRules.first)
        #expect(removed.ruleId == "opaque_over_existential")
        #expect(removed.removedInVersion == "0.59.1")
        #expect(removed.replacement == nil)
    }

    @Test("Removed rule not detected for earlier version")
    func testRemovedRuleNotDetectedForEarlierVersion() {
        let config = makeConfig(rules: ["anyobject_protocol": RuleConfiguration(enabled: true)])
        // anyobject_protocol removed in 0.57.0, so 0.56.0 should not flag it as removed
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.56.0")
        #expect(report.removedRules.isEmpty)
    }

    /// Both were removed in 0.7.0 and their limits became `variable_name`'s (now
    /// `identifier_name`'s) `min_length` and `max_length`. A rename would move a bare
    /// threshold onto `identifier_name`, overwriting any configuration it already has.
    @Test("Reports a merged rule as removed, not renamed", arguments: [
        "variable_name_max_length", "variable_name_min_length"
    ])
    func testMergedRuleIsRemovedNotRenamed(ruleId: String) throws {
        let config = makeConfig(rules: [ruleId: RuleConfiguration(enabled: true)])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.65.0")
        #expect(report.renamedRules.isEmpty)
        #expect(report.deprecatedRules.isEmpty)
        let removed = try #require(report.removedRules.first)
        #expect(removed.ruleId == ruleId)
        #expect(removed.removedInVersion == "0.7.0")
        #expect(removed.replacement == "identifier_name")
    }

    // MARK: - Renamed Rules

    @Test("Detects renamed rules")
    func testDetectsRenamedRules() throws {
        let config = makeConfig(rules: ["variable_name": RuleConfiguration(enabled: true)])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.55.0")
        let renamed = try #require(report.renamedRules.first { $0.oldRuleId == "variable_name" })
        #expect(renamed.newRuleId == "identifier_name")
    }

    /// SwiftLint 0.65.0 still accepts `variable_name` as a deprecated alias of `identifier_name`.
    @Test("Reports a deprecated alias as deprecated, never removed")
    func testDeprecatedAliasIsNotRemoved() throws {
        let config = makeConfig(rules: ["variable_name": RuleConfiguration(enabled: true)])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.65.0")
        #expect(report.removedRules.isEmpty)
        let deprecated = try #require(report.deprecatedRules.first)
        #expect(deprecated.ruleId == "variable_name")
        #expect(deprecated.deprecatedInVersion == "0.17.0")
        #expect(deprecated.replacement == "identifier_name")
    }

    /// `if_let_shadowing` shipped only in 0.50.0-rc.1; 0.50.0 calls it
    /// `shorthand_optional_binding` and keeps the old name as an alias.
    @Test("Reports if_let_shadowing as renamed once shorthand_optional_binding exists", arguments: [
        ("0.49.0", false), ("0.50.0", true), ("0.65.0", true)
    ])
    func testIfLetShadowingRename(version: String, renamed: Bool) {
        let config = makeConfig(optInRules: ["if_let_shadowing"])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: version)
        let rename = RenamedRuleInfo(
            id: "if_let_shadowing", oldRuleId: "if_let_shadowing", newRuleId: "shorthand_optional_binding"
        )
        #expect(report.renamedRules.contains(rename) == renamed)
    }

    /// Both rules still exist in 0.65.0, next to the rules the table once renamed them to.
    /// `multiple_closures_with_trailing_closure` is on by default and `trailing_closure` is
    /// opt-in, so the "fix" changed what the config linted.
    @Test("Does not flag a rule that still exists", arguments: [
        "multiple_closures_with_trailing_closure", "generic_type_name"
    ])
    func testDoesNotFlagLiveRule(ruleId: String) {
        let config = makeConfig(rules: [ruleId: RuleConfiguration(enabled: true)])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.65.0")
        #expect(report.hasIssues == false)
    }

    /// No rule replaced these: `unused_closure_use` never existed, and `no_empty_block`
    /// is an unrelated opt-in rule.
    @Test("Reports a rule the compiler replaced as removed, not renamed", arguments: [
        "unused_capture_list", "inert_defer"
    ])
    func testCompilerReplacedRuleIsRemovedNotRenamed(ruleId: String) throws {
        let config = makeConfig(optInRules: [ruleId])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.65.0")
        #expect(report.renamedRules.isEmpty)
        let removed = try #require(report.removedRules.first)
        #expect(removed.ruleId == ruleId)
        #expect(removed.removedInVersion == "0.58.0")
        #expect(removed.replacement == nil)
    }

    // MARK: - Disabled Rules List

    @Test("Detects deprecated rules in disabled_rules list")
    func testDetectsDeprecatedInDisabledList() {
        let config = makeConfig(disabledRules: ["variable_name"])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.55.0")
        #expect(report.deprecatedRules.map(\.ruleId) == ["variable_name"])
        #expect(report.renamedRules.map(\.oldRuleId) == ["variable_name"])
    }

    // MARK: - New Rules Available

    @Test("Reports new rules available in current version")
    func testNewRulesAvailable() {
        let config = makeConfig(rules: ["force_cast": RuleConfiguration(enabled: true)])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.55.0")
        #expect(report.availableNewRules.isEmpty == false)
    }

    /// Additions are dated by the first release whose source declares the rule. These were
    /// misdated by up to 17 minor versions; the CHANGELOG itself is wrong about the last two.
    @Test("Offers a rule as new from the release that shipped it", arguments: [
        ("overridden_super_call", "0.12.0", "0.13.0"),
        ("prefer_self_in_static_references", "0.45.0", "0.45.1"),
        ("non_overridable_class_declaration", "0.52.0", "0.53.0"),
        ("no_empty_block", "0.55.0", "0.56.0"),
        ("file_name_no_space", "0.38.0", "0.38.1"),
        ("attribute_name_spacing", "0.56.0", "0.57.0")
    ])
    func testNewRuleArrivesWithItsRelease(rule: String, before: String, shippedIn: String) {
        let config = makeConfig()
        let beforeReport = checker.checkCompatibility(config: config, swiftLintVersion: before)
        let shippedReport = checker.checkCompatibility(config: config, swiftLintVersion: shippedIn)
        #expect(beforeReport.availableNewRules.contains(rule) == false)
        #expect(shippedReport.availableNewRules.contains(rule))
    }

    /// `anyobject_protocol` was added in 0.27.0 and removed in 0.57.0; `opaque_over_existential`
    /// shipped only in 0.59.0.
    @Test("Does not offer a removed rule as new", arguments: [
        ("anyobject_protocol", "0.56.0", true), ("anyobject_protocol", "0.57.0", false),
        ("anyobject_protocol", "0.65.0", false),
        ("opaque_over_existential", "0.59.0", true), ("opaque_over_existential", "0.59.1", false)
    ])
    func testRemovedRuleIsNotNew(rule: String, version: String, offered: Bool) {
        let report = checker.checkCompatibility(config: makeConfig(), swiftLintVersion: version)
        #expect(report.availableNewRules.contains(rule) == offered)
    }

    // MARK: - Clean Report

    @Test("Clean config has no issues")
    func testCleanReportHasNoIssues() {
        let config = makeConfig(rules: [
            "identifier_name": RuleConfiguration(enabled: true),
            "line_length": RuleConfiguration(enabled: true)
        ])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.55.0")
        // identifier_name is not deprecated/removed/renamed
        #expect(report.removedRules.isEmpty)
    }

    // MARK: - Version Comparison Helper

    @Test("Version comparison works correctly")
    func testVersionComparison() {
        #expect(SwiftLintDeprecations.isVersion("0.24.0", lessThan: "0.25.0"))
        #expect(SwiftLintDeprecations.isVersion("0.25.0", lessThan: "0.25.0") == false)
        #expect(SwiftLintDeprecations.isVersion("0.26.0", lessThan: "0.25.0") == false)
        #expect(SwiftLintDeprecations.isVersion("0.9.0", lessThan: "0.10.0"))
    }

    @Test("Rules added between versions")
    func testRulesAddedBetweenVersions() {
        // identifier_name arrived in 0.17.0 as variable_name's new name
        let rules = SwiftLintDeprecations.rulesAdded(from: "0.16.0", to: "0.17.0")
        #expect(rules.contains("identifier_name"))
    }
}
