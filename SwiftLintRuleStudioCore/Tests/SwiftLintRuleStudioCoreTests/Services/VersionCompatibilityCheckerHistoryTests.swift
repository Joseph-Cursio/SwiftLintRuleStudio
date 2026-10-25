//
//  VersionCompatibilityCheckerHistoryTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  VersionCompatibilityChecker against SwiftLint's rule history: each removal,
//  rename and deprecation at the release tag that made it, rules used under an
//  alias, and pre-release versions.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct VersionCompatibilityCheckerHistoryTests {

    private let checker = VersionCompatibilityChecker()

    private func makeConfig(
        rules: [String: RuleConfiguration] = [:],
        optInRules: [String]? = nil
    ) -> YAMLConfigurationEngine.YAMLConfig {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules = rules
        config.optInRules = optInRules
        return config
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

    @Test("New rules available leave out a rule the config uses under an old name")
    func testNewRulesExcludeRulesUsedThroughAnAlias() {
        let aliased = checker.checkCompatibility(
            config: makeConfig(optInRules: ["redundant_optional_initialization"]), swiftLintVersion: "0.65.0"
        )
        #expect(aliased.availableNewRules.contains("implicit_optional_initialization") == false)
        let clean = checker.checkCompatibility(config: makeConfig(), swiftLintVersion: "0.65.0")
        #expect(clean.availableNewRules.contains("implicit_optional_initialization"))
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
}
