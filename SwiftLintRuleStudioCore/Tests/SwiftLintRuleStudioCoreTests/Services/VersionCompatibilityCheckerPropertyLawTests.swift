//
//  VersionCompatibilityCheckerPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for `VersionCompatibilityChecker.checkCompatibility`: what a
//  compatibility report contains for a configuration and an installed SwiftLint
//  version. Mutation testing left four of the file's six mutants undetected. The
//  example tests never reached a version between a rule's deprecation and its
//  removal, so flipping either version check went unnoticed, and nothing read
//  `hasIssues`.
//
//  The report is a decision table over the deprecation data, for installed
//  version v:
//
//      deprecated r   r is configured, deprecated at or before v, and not
//                     removed at or before v (a removed rule is reported as
//                     removed instead — the two sections never overlap)
//      removed r      r is configured and removed at or before v
//      renamed r → t  r is configured, t is its rename, and v has t: not below
//                     the version r was renamed in
//      new rules      every rule added at or before v, not removed at or before
//                     v, that the config does not mention
//
//  `hasIssues == (totalIssueCount > 0)` is not stated here: swift-infer proposes
//  it (`emptiness-agreement`) and its generated stub states it.
//
//  Writing the rename law found the defect MigrationAssistant had, fixed in the
//  same change: renames ignored the installed version, so a config checked
//  against 0.16 reported `variable_name` as renamed to `identifier_name`, which
//  only exists from 0.17.
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

/// A generated configuration and installed version, kept to primitives so it can
/// cross the generator boundary — `YAMLConfig` is main-actor-isolated.
private struct CompatibilitySpec: Sendable {
    /// Each configured rule: an index into the vocabulary, and which field holds it.
    let rules: [Placement]
    let versionIndex: Int

    struct Placement: Sendable, Hashable {
        let rule: Int
        let field: Int
    }
}

@MainActor
@Suite("Version compatibility checker property laws")
struct VersionCompatibilityCheckerPropertyLawTests {

    private static let checker = VersionCompatibilityChecker()

    /// Every rule the deprecation data names, every rename target, every added rule, and two rules
    /// it does not mention.
    private static let vocabulary: [String] = {
        let named = Set(SwiftLintDeprecations.renamedRules.keys)
            .union(SwiftLintDeprecations.renamedRules.values)
            .union(SwiftLintDeprecations.deprecatedRules.keys)
            .union(SwiftLintDeprecations.removedRules.keys)
            .union(SwiftLintDeprecations.versionRuleAdditions.values.joined())
        return named.union(["line_length", "force_cast"]).sorted()
    }()

    /// Every version the data turns on, and the version just below each, where a
    /// window's edge would show.
    private static let versions: [String] = {
        let turning = SwiftLintDeprecations.deprecatedRules.values.map(\.deprecatedInVersion)
            + SwiftLintDeprecations.removedRules.values.map(\.removedInVersion)
            + Array(SwiftLintDeprecations.versionRuleAdditions.keys)
        let below = turning.compactMap { version -> String? in
            let parts = version.split(separator: ".").compactMap { Int($0) }
            guard parts.count == 3, parts[1] > 0 else { return nil }
            return "0.\(parts[1] - 1).0"
        }
        return Set(turning + below + ["0.20.0", "0.70.0"]).sorted {
            SwiftLintDeprecations.isVersion($0, lessThan: $1)
        }
    }()

    // MARK: - Generators

    private static func specGenerator() -> Generator<CompatibilitySpec, some SendableSequenceType> {
        let placement = zip(
            Gen<Int>.int(in: 0 ... (vocabulary.count - 1)),
            Gen<Int>.int(in: 0...4)
        ).map { CompatibilitySpec.Placement(rule: $0, field: $1) }
        return zip(
            placement.array(of: 0...8),
            Gen<Int>.int(in: 0 ... (versions.count - 1))
        ).map { CompatibilitySpec(rules: $0, versionIndex: $1) }
    }

    // MARK: - Construction

    /// The configuration `spec` describes. Field 0 is the rules dictionary; the
    /// rest are the four rule lists.
    private static func config(for spec: CompatibilitySpec) -> YAMLConfigurationEngine.YAMLConfig {
        var config = YAMLConfigurationEngine.YAMLConfig()
        var lists: [[String]] = Array(repeating: [], count: 4)
        for placement in spec.rules {
            let rule = vocabulary[placement.rule]
            if placement.field == 0 {
                config.rules[rule] = RuleConfiguration(enabled: true)
            } else if !lists[placement.field - 1].contains(rule) {
                lists[placement.field - 1].append(rule)
            }
        }
        config.disabledRules = lists[0].isEmpty ? nil : lists[0]
        config.optInRules = lists[1].isEmpty ? nil : lists[1]
        config.analyzerRules = lists[2].isEmpty ? nil : lists[2]
        config.onlyRules = lists[3].isEmpty ? nil : lists[3]
        return config
    }

    private static func configuredIds(_ config: YAMLConfigurationEngine.YAMLConfig) -> Set<String> {
        Set(config.rules.keys)
            .union(config.disabledRules ?? [])
            .union(config.optInRules ?? [])
            .union(config.analyzerRules ?? [])
            .union(config.onlyRules ?? [])
    }

    private static func report(for spec: CompatibilitySpec) -> CompatibilityReport {
        checker.checkCompatibility(config: config(for: spec), swiftLintVersion: versions[spec.versionIndex])
    }

    /// Whether `version` is at or past `threshold`.
    private static func reached(_ threshold: String, by version: String) -> Bool {
        !SwiftLintDeprecations.isVersion(version, lessThan: threshold)
    }

    // MARK: - Laws

    @Test("a configured rule is reported deprecated exactly when deprecated by v and not yet removed")
    func deprecatedFollowsTheTable() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let version = Self.versions[spec.versionIndex]
            let configured = Self.configuredIds(Self.config(for: spec)).sorted()
            let expected = configured.compactMap { rule -> DeprecatedRuleInfo? in
                guard let entry = SwiftLintDeprecations.deprecatedRules[rule],
                      Self.reached(entry.deprecatedInVersion, by: version) else { return nil }
                if let removal = SwiftLintDeprecations.removedRules[rule],
                   Self.reached(removal.removedInVersion, by: version) { return nil }
                return DeprecatedRuleInfo(
                    id: rule, ruleId: rule, deprecatedInVersion: entry.deprecatedInVersion,
                    replacement: entry.replacement, message: entry.message
                )
            }
            #expect(Self.report(for: spec).deprecatedRules == expected)
        }
    }

    @Test("a configured rule is reported removed exactly when removed by v")
    func removedFollowsTheTable() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let version = Self.versions[spec.versionIndex]
            let configured = Self.configuredIds(Self.config(for: spec)).sorted()
            let expected = configured.compactMap { rule -> RemovedRuleInfo? in
                guard let entry = SwiftLintDeprecations.removedRules[rule],
                      Self.reached(entry.removedInVersion, by: version) else { return nil }
                return RemovedRuleInfo(
                    id: rule, ruleId: rule, removedInVersion: entry.removedInVersion,
                    replacement: entry.replacement, message: entry.message
                )
            }
            #expect(Self.report(for: spec).removedRules == expected)
        }
    }

    @Test("a configured rule is reported renamed exactly when v has its new name")
    func renamedFollowsTheTable() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let version = Self.versions[spec.versionIndex]
            let configured = Self.configuredIds(Self.config(for: spec)).sorted()
            let expected = configured.compactMap { rule -> RenamedRuleInfo? in
                guard let target = SwiftLintDeprecations.renamedRules[rule], target != rule else { return nil }
                if let renamedIn = SwiftLintDeprecations.deprecatedRules[rule]?.deprecatedInVersion,
                   !Self.reached(renamedIn, by: version) { return nil }
                return RenamedRuleInfo(id: rule, oldRuleId: rule, newRuleId: target)
            }
            #expect(Self.report(for: spec).renamedRules == expected)
        }
    }

    /// The code's own comment: a removed rule "will appear in removed rules".
    @Test("no rule is reported both deprecated and removed")
    func deprecatedAndRemovedAreDisjoint() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let report = Self.report(for: spec)
            #expect(Set(report.deprecatedRules.map(\.ruleId)).isDisjoint(with: report.removedRules.map(\.ruleId)))
        }
    }

    @Test("the new rules are every rule added by v, and not removed by v, that the config does not mention")
    func newRulesFollowTheAdditions() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let version = Self.versions[spec.versionIndex]
            let added = SwiftLintDeprecations.versionRuleAdditions
                .filter { Self.reached($0.key, by: version) }
                .flatMap(\.value)
                .filter { rule in
                    guard let removedIn = SwiftLintDeprecations.removedRules[rule]?.removedInVersion else {
                        return true
                    }
                    return !Self.reached(removedIn, by: version)
                }
            let expected = Set(added).subtracting(Self.configuredIds(Self.config(for: spec))).sorted()
            #expect(Self.report(for: spec).availableNewRules == expected)
        }
    }

    // MARK: - The version gate, pinned

    /// The defect the rename law found: `identifier_name` arrived in 0.17.0.
    @Test("a rename is not reported before the installed version has the new name", arguments: [
        ("0.15.0", false), ("0.16.0", false), ("0.17.0", true), ("0.40.0", true)
    ])
    func renameWaitsForTheInstalledVersion(version: String, renamed: Bool) {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules = ["variable_name": RuleConfiguration(enabled: true)]
        let report = Self.checker.checkCompatibility(config: config, swiftLintVersion: version)
        #expect(report.renamedRules.contains { $0.oldRuleId == "variable_name" } == renamed)
    }

    /// Deprecated in 0.51.0, removed in 0.58.0: the three sides of that window.
    @Test("unused_capture_list is deprecated inside its window and removed after it", arguments: [
        ("0.50.0", false, false), ("0.51.0", true, false), ("0.57.0", true, false), ("0.58.0", false, true)
    ])
    func deprecationWindow(version: String, deprecated: Bool, removed: Bool) {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.optInRules = ["unused_capture_list"]
        let report = Self.checker.checkCompatibility(config: config, swiftLintVersion: version)
        #expect(report.deprecatedRules.contains { $0.ruleId == "unused_capture_list" } == deprecated)
        #expect(report.removedRules.contains { $0.ruleId == "unused_capture_list" } == removed)
    }
}
