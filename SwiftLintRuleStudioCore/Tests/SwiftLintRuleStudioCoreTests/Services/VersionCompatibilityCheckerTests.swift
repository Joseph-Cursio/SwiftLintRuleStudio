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
        // unused_capture_list was deprecated in 0.51.0, for a compiler warning, and removed in 0.58.0
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.55.0")
        let deprecated = try #require(report.deprecatedRules.first { $0.ruleId == "unused_capture_list" })
        #expect(deprecated.deprecatedInVersion == "0.51.0")
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
        let config = makeConfig(rules: ["unused_capture_list": RuleConfiguration(enabled: true)])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.58.0")
        let removedRule = try #require(report.removedRules.first)
        #expect(removedRule.ruleId == "unused_capture_list")
        #expect(removedRule.replacement == nil)
        #expect(report.deprecatedRules.isEmpty)
    }

    @Test("Removed rule not detected for earlier version")
    func testRemovedRuleNotDetectedForEarlierVersion() {
        let config = makeConfig(rules: ["unused_capture_list": RuleConfiguration(enabled: true)])
        // unused_capture_list removed in 0.58.0, so 0.57.0 should not flag it as removed
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.57.0")
        #expect(report.removedRules.isEmpty)
    }

    @Test("Rules removed with no replacement are reported from their removal on", arguments: [
        ("weak_computed_property", "0.32.0", "0.33.0"),
        ("unneeded_notification_center_removal", "0.40.0", "0.41.0"),
        ("opaque_over_existential", "0.59.0", "0.59.1")
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

    /// SwiftLint 0.65 still resolves `variable_name` as `identifier_name`'s alias.
    @Test("A renamed rule is never reported removed")
    func testRenamedRuleIsNotRemoved() {
        let config = makeConfig(rules: ["variable_name": RuleConfiguration(enabled: true)])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.65.0")
        #expect(report.removedRules.isEmpty)
    }

    // MARK: - Renamed Rules

    @Test("Detects renamed rules")
    func testDetectsRenamedRules() throws {
        let config = makeConfig(rules: ["variable_name": RuleConfiguration(enabled: true)])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.55.0")
        let renamed = try #require(report.renamedRules.first { $0.oldRuleId == "variable_name" })
        #expect(renamed.newRuleId == "identifier_name")
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

    /// Issue #83's config lists `generic_type_name` and `multiple_closures_with_trailing_closure`
    /// under `only_rules`. Both are live rules; "Fix" used to rewrite them to `identifier_name`
    /// and `trailing_closure`, different rules.
    @Test("Live rules once listed as renamed are clean", arguments: [
        "generic_type_name", "multiple_closures_with_trailing_closure", "trailing_closure", "type_name"
    ])
    func testLiveRulesAreNotRenamed(ruleId: String) {
        var config = makeConfig()
        config.onlyRules = [ruleId]
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.65.0")
        #expect(report.hasIssues == false)
    }

    @Test("Rules dropped for compiler warnings are not renamed", arguments: ["inert_defer", "unused_capture_list"])
    func testCompilerWarningRulesAreNotRenamed(ruleId: String) throws {
        let config = makeConfig(optInRules: [ruleId])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.65.0")
        #expect(report.renamedRules.isEmpty)
        let removed = try #require(report.removedRules.first { $0.ruleId == ruleId })
        #expect(removed.removedInVersion == "0.58.0")
        // Not `no_empty_block`, which the tables once named as inert_defer's replacement.
        #expect(removed.replacement == nil)
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
        #expect(report.renamedRules.map(\.newRuleId) == ["identifier_name"])
    }

    // MARK: - New Rules Available

    @Test("Reports new rules available in current version")
    func testNewRulesAvailable() {
        let config = makeConfig(rules: ["force_cast": RuleConfiguration(enabled: true)])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.55.0")
        #expect(report.availableNewRules.isEmpty == false)
    }

    /// `anyobject_protocol` was added in 0.27.0, deprecated with no replacement in 0.50.0, and
    /// removed in 0.57.0.
    @Test("New rules available leave out a rule the installed version has retired", arguments: [
        ("0.49.0", true), ("0.50.0", false), ("0.57.0", false), ("0.65.0", false)
    ])
    func testNewRulesExcludeRemovedRules(version: String, suggested: Bool) {
        let report = checker.checkCompatibility(config: makeConfig(), swiftLintVersion: version)
        #expect(report.availableNewRules.contains("anyobject_protocol") == suggested)
    }

    @Test("no_empty_block is available from 0.56.0", arguments: [("0.55.0", false), ("0.56.0", true)])
    func testNoEmptyBlockAvailability(version: String, available: Bool) {
        let report = checker.checkCompatibility(config: makeConfig(), swiftLintVersion: version)
        #expect(report.availableNewRules.contains("no_empty_block") == available)
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
        let rules = SwiftLintDeprecations.rulesAdded(from: "0.16.0", to: "0.17.0")
        #expect(rules.contains("identifier_name"))
    }

    /// `anyobject_protocol`: added 0.27.0, deprecated with no replacement 0.50.0, removed 0.57.0.
    @Test("Rules added between versions leave out a rule the target version has retired", arguments: [
        ("0.49.0", true), ("0.50.0", false), ("0.65.0", false)
    ])
    func testRulesAddedExcludeRetiredRules(toVersion: String, included: Bool) {
        let rules = SwiftLintDeprecations.rulesAdded(from: "0.26.0", to: toVersion)
        #expect(rules.contains("anyobject_protocol") == included)
        #expect(rules.contains("collection_alignment"))
    }
}
