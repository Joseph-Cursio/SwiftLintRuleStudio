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

    @Test("Rules removed with no replacement are reported from their removal on", arguments: [
        ("conditional_binding_cascade", "0.11.1", "0.11.2"),
        ("valid_docs", "0.18.1", "0.19.0"),
        ("weak_computed_property", "0.32.0", "0.33.0"),
        ("tuple_pattern", "0.39.0", "0.39.1"),
        ("prohibited_nan_comparison", "0.39.0", "0.39.1"),
        ("unneeded_notification_center_removal", "0.40.0", "0.41.0")
    ])
    func testRemovedWithoutReplacement(ruleId: String, lastVersionWithIt: String, removedIn: String) throws {
        let config = makeConfig(optInRules: [ruleId])
        let before = checker.checkCompatibility(config: config, swiftLintVersion: lastVersionWithIt)
        #expect(before.removedRules.isEmpty)
        let after = checker.checkCompatibility(config: config, swiftLintVersion: removedIn)
        let removed = try #require(after.removedRules.first)
        #expect(removed.ruleId == ruleId)
        #expect(removed.replacement == nil)
        #expect(after.renamedRules.isEmpty)
    }

    /// Neither old id is an alias, so neither is a rename: the misspelled
    /// `redundant_nil_coalesing` was corrected without one, and `unused_private_declaration`
    /// gave way to the analyzer rule `unused_declaration`.
    @Test("Rules removed for another are reported removed, pointing at it", arguments: [
        ("redundant_nil_coalesing", "0.13.0", "0.13.1", "redundant_nil_coalescing"),
        ("unused_private_declaration", "0.33.1", "0.34.0", "unused_declaration")
    ])
    func testRemovedWithReplacement(ruleId: String, lastVersionWithIt: String, removedIn: String, replacement: String)
        throws {
        var config = makeConfig()
        config.analyzerRules = [ruleId]
        #expect(checker.checkCompatibility(config: config, swiftLintVersion: lastVersionWithIt).removedRules.isEmpty)
        let report = checker.checkCompatibility(config: config, swiftLintVersion: removedIn)
        let removed = try #require(report.removedRules.first)
        #expect(removed.ruleId == ruleId)
        #expect(removed.replacement == replacement)
        #expect(report.renamedRules.isEmpty)
    }

    /// Deprecated in 0.50.0 for a compiler check, removed in 0.57.0.
    @Test("anyobject_protocol is deprecated from 0.50.0 and removed from 0.57.0", arguments: [
        ("0.49.0", false, false), ("0.50.0", true, false), ("0.56.0", true, false), ("0.57.0", false, true)
    ])
    func testAnyObjectProtocolLifecycle(version: String, deprecated: Bool, removed: Bool) {
        let config = makeConfig(optInRules: ["anyobject_protocol"])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: version)
        #expect(report.deprecatedRules.contains { $0.ruleId == "anyobject_protocol" } == deprecated)
        #expect(report.removedRules.contains { $0.ruleId == "anyobject_protocol" } == removed)
    }

    @Test("variable_name_max_length is removed from 0.7.0", arguments: [("0.6.0", false), ("0.7.0", true)])
    func testVariableNameMaxLengthRemoval(version: String, removed: Bool) {
        let report = checker.checkCompatibility(
            config: makeConfig(rules: ["variable_name_max_length": RuleConfiguration(enabled: true)]),
            swiftLintVersion: version
        )
        #expect(report.removedRules.contains { $0.ruleId == "variable_name_max_length" } == removed)
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

    @Test("Each SwiftLint alias is reported renamed to the rule that declares it", arguments: [
        ("variable_name", "identifier_name"),
        ("if_let_shadowing", "shorthand_optional_binding"),
        ("redundant_optional_initialization", "implicit_optional_initialization"),
        ("operator_whitespace", "function_name_whitespace"),
        ("redundant_self_in_closure", "redundant_self")
    ])
    func testAliasesAreRenamed(oldId: String, newId: String) {
        let config = makeConfig(optInRules: [oldId])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.65.0")
        #expect(report.renamedRules == [RenamedRuleInfo(id: oldId, oldRuleId: oldId, newRuleId: newId)])
    }

    /// `redundant_self_in_closure: error` is a severity shorthand the engine keeps as a
    /// passthrough node, not in `rules`; "Fix" used to leave it and the re-check came back clean.
    @Test("A renamed rule configured by a severity shorthand is reported")
    func testRenamedSeverityShorthandIsReported() throws {
        let config = try YAMLConfigurationEngine.parse("redundant_self_in_closure: error\n")
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.65.0")
        #expect(report.renamedRules.map(\.newRuleId) == ["redundant_self"])
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
    /// misdated by up to 17 minor versions; the CHANGELOG itself is wrong about `file_name_no_space`,
    /// `attribute_name_spacing` and `legacy_swiftui_aspect_ratio`.
    @Test("Offers a rule as new from the release that shipped it", arguments: [
        ("overridden_super_call", "0.12.0", "0.13.0"),
        ("prefer_self_in_static_references", "0.45.0", "0.45.1"),
        ("non_overridable_class_declaration", "0.52.0", "0.53.0"),
        ("no_empty_block", "0.55.0", "0.56.0"),
        ("file_name_no_space", "0.38.0", "0.38.1"),
        ("attribute_name_spacing", "0.56.0", "0.57.0"),
        ("prefer_type_checking", "0.56.0", "0.57.0"),
        ("legacy_swiftui_aspect_ratio", "0.65.0", "0.65.1")
    ])
    func testNewRuleArrivesWithItsRelease(rule: String, before: String, shippedIn: String) {
        let config = makeConfig()
        let beforeReport = checker.checkCompatibility(config: config, swiftLintVersion: before)
        let shippedReport = checker.checkCompatibility(config: config, swiftLintVersion: shippedIn)
        #expect(beforeReport.availableNewRules.contains(rule) == false)
        #expect(shippedReport.availableNewRules.contains(rule))
    }

    /// `anyobject_protocol` was added in 0.27.0, deprecated with no replacement in 0.50.0 and
    /// removed in 0.57.0; `opaque_over_existential` shipped only in 0.59.0.
    @Test("Does not offer a retired rule as new", arguments: [
        ("anyobject_protocol", "0.49.0", true), ("anyobject_protocol", "0.50.0", false),
        ("anyobject_protocol", "0.57.0", false), ("anyobject_protocol", "0.65.0", false),
        ("opaque_over_existential", "0.59.0", true), ("opaque_over_existential", "0.59.1", false)
    ])
    func testRemovedRuleIsNotNew(rule: String, version: String, offered: Bool) {
        let report = checker.checkCompatibility(config: makeConfig(), swiftLintVersion: version)
        #expect(report.availableNewRules.contains(rule) == offered)
    }

    @Test("New rules available leave out a rule the config uses under an old name")
    func testNewRulesExcludeRulesUsedThroughAnAlias() {
        let aliased = checker.checkCompatibility(
            config: makeConfig(optInRules: ["redundant_optional_initialization"]), swiftLintVersion: "0.65.0"
        )
        #expect(aliased.availableNewRules.contains("implicit_optional_initialization") == false)
        let clean = checker.checkCompatibility(config: makeConfig(), swiftLintVersion: "0.65.0")
        #expect(clean.availableNewRules.contains("implicit_optional_initialization"))
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

    @Test("Version comparison follows semver precedence, ignoring a leading v and build metadata", arguments: [
        ("v0.30.0", "0.31.0", true), ("V0.31.0", "0.30.0", false), ("v0.30.0", "0.30.0", false),
        ("0.30.0", "v0.30.0", false), ("0.50.0-rc.2", "0.50.0", true), ("0.50.0", "0.50.0-rc.2", false),
        ("0.49.1", "0.50.0-rc.2", true), ("0.65.0+build.5", "0.65.1", true),
        ("0.50.0-rc.1", "0.50.0-rc.2", true), ("0.50.0-rc.2", "0.50.0-rc.10", true),
        ("0.50.0-rc.1", "0.50.0-rc.1", false), ("0.50.0-rc", "0.50.0-rc.1", true),
        ("0.50.0-1", "0.50.0-rc", true), ("0.50.0-alpha", "0.50.0-rc.1", true),
        ("0.65.0+build.5", "0.65.0", false), ("0.65.0", "0.65.0+build.5", false),
        ("v0.50.0-rc.1+sha.1", "0.50.0", true)
    ])
    func testVersionComparisonFollowsSemver(lhs: String, rhs: String, lessThan: Bool) {
        #expect(SwiftLintDeprecations.isVersion(lhs, lessThan: rhs) == lessThan)
    }

    /// 0.50.0-rc.1 registers `if_let_shadowing`; rc.2 renamed it, keeping the old id as an alias.
    @Test("A pre-release is not told about a rename its release brings", arguments: [
        ("0.50.0-rc.1", false), ("0.50.0-rc.2", false), ("0.50.0", true)
    ])
    func testPreReleaseRename(version: String, renamed: Bool) {
        let config = makeConfig(optInRules: ["if_let_shadowing"])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: version)
        #expect(report.renamedRules.contains { $0.oldRuleId == "if_let_shadowing" } == renamed)
        #expect(report.availableNewRules.contains("shorthand_optional_binding") == false)
    }

    @Test("Rules added between versions")
    func testRulesAddedBetweenVersions() {
        // identifier_name arrived in 0.17.0 as variable_name's new name
        let rules = SwiftLintDeprecations.rulesAdded(from: "0.16.0", to: "0.17.0")
        #expect(rules.contains("identifier_name"))
    }
}
