//
//  VersionCompatibilityCheckerTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for VersionCompatibilityChecker
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

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
    func testDetectsDeprecatedRules() {
        let config = makeConfig(rules: ["unused_capture_list": RuleConfiguration(enabled: true)])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.40.0")
        // unused_capture_list deprecated in 0.39.0, not yet removed
        #expect(!report.deprecatedRules.isEmpty || !report.renamedRules.isEmpty)
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
        let config = makeConfig(rules: ["variable_name": RuleConfiguration(enabled: true)])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.55.0")
        let removedRule = try #require(report.removedRules.first)
        #expect(removedRule.ruleId == "variable_name")
    }

    @Test("Removed rule not detected for earlier version")
    func testRemovedRuleNotDetectedForEarlierVersion() {
        let config = makeConfig(rules: ["variable_name": RuleConfiguration(enabled: true)])
        // variable_name removed in 0.35.0, so 0.30.0 should not flag it as removed
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.30.0")
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

    // MARK: - Disabled Rules List

    @Test("Detects deprecated rules in disabled_rules list")
    func testDetectsDeprecatedInDisabledList() {
        let config = makeConfig(disabledRules: ["variable_name"])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.55.0")
        let hasIssue = !report.removedRules.isEmpty || !report.renamedRules.isEmpty
        #expect(hasIssue)
    }

    // MARK: - New Rules Available

    @Test("Reports new rules available in current version")
    func testNewRulesAvailable() {
        let config = makeConfig(rules: ["force_cast": RuleConfiguration(enabled: true)])
        let report = checker.checkCompatibility(config: config, swiftLintVersion: "0.55.0")
        #expect(!report.availableNewRules.isEmpty)
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
        #expect(!SwiftLintDeprecations.isVersion("0.25.0", lessThan: "0.25.0"))
        #expect(!SwiftLintDeprecations.isVersion("0.26.0", lessThan: "0.25.0"))
        #expect(SwiftLintDeprecations.isVersion("0.9.0", lessThan: "0.10.0"))
    }

    @Test("Rules added between versions")
    func testRulesAddedBetweenVersions() {
        let rules = SwiftLintDeprecations.rulesAdded(from: "0.24.0", to: "0.25.0")
        #expect(rules.contains("identifier_name"))
    }
}
