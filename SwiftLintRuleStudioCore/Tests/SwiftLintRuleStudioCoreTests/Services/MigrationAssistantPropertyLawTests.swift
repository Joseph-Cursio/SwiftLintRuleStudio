//
//  MigrationAssistantPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for `MigrationAssistant`: what a migration plan contains for a
//  configuration and a version range, and what applying it does. Mutation
//  testing left eight of the file's ten mutants alive. The example tests asked
//  for *a* rename step and never for the plan's exact contents, so a duplicated
//  step, a removal for a rule already being renamed, and a removal outside its
//  version window all passed. No example used a removed rule that is not also
//  renamed (`anyobject_protocol`, then the only one), and none emptied a list.
//
//  The laws are a decision table over the deprecation data:
//
//      rename r → t     r is configured, t is r's rename (or its deprecation's
//                       replacement), t ≠ r, and the target version has t: not
//                       below the version r was renamed in
//      remove r         r is configured, r was removed in a version v with
//                       from < v ≤ to, and r is not being renamed
//      new-rules note   a rule was added after `from`, up to `to`, and `to`
//                       has not removed it; the note lists exactly those rules
//
//  and two laws over `applyMigration`. It is idempotent, the law swift-infer
//  proposed for it once the linter seeded it as a pure mutator. And it leaves
//  no renamed or removed id behind, nothing else touched, and no list empty
//  rather than absent.
//
//  Writing the rename law found a defect, fixed in the same change: renames
//  ignored the target version, so a 0.10 → 0.16 migration renamed
//  `variable_name` to `identifier_name`, which only exists from 0.17.
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

/// A generated configuration and version range, kept to primitives so it can
/// cross the generator boundary — `YAMLConfig` is main-actor-isolated.
private struct MigrationSpec: Sendable {
    /// Each configured rule: an index into the vocabulary, and which field holds it.
    let rules: [Placement]
    let fromIndex: Int
    let toIndex: Int

    struct Placement: Sendable, Hashable {
        let rule: Int
        let field: Int
    }
}

@MainActor
@Suite("Migration assistant property laws")
struct MigrationAssistantPropertyLawTests {

    private static let assistant = MigrationAssistant()

    /// Every rule the deprecation data names, every rename target, and two rules
    /// it does not mention, so a law is checked on rules it must leave alone.
    private static let vocabulary: [String] = {
        let named = Set(SwiftLintDeprecations.renamedRules.keys)
            .union(SwiftLintDeprecations.renamedRules.values)
            .union(SwiftLintDeprecations.deprecatedRules.keys)
            .union(SwiftLintDeprecations.removedRules.keys)
        return named.union(["line_length", "force_cast"]).sorted()
    }()

    /// Every version the data turns on, and the version just below each, where
    /// a window's edge would show.
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

    private static func specGenerator() -> Generator<MigrationSpec, some SendableSequenceType> {
        let placement = zip(
            Gen<Int>.int(in: 0 ... (vocabulary.count - 1)),
            Gen<Int>.int(in: 0...4)
        ).map { MigrationSpec.Placement(rule: $0, field: $1) }
        return zip(
            placement.array(of: 0...6),
            Gen<Int>.int(in: 0 ... (versions.count - 1)),
            Gen<Int>.int(in: 0 ... (versions.count - 1))
        ).map { MigrationSpec(rules: $0, fromIndex: $1, toIndex: $2) }
    }

    // MARK: - Construction

    /// The configuration `spec` describes. Field 0 is the rules dictionary; the
    /// rest are the four rule lists, each left absent rather than empty.
    private static func config(for spec: MigrationSpec) -> YAMLConfigurationEngine.YAMLConfig {
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

    private static func plan(for spec: MigrationSpec) -> MigrationPlan {
        assistant.detectMigrations(
            config: config(for: spec),
            fromVersion: versions[spec.fromIndex],
            toVersion: versions[spec.toIndex]
        )
    }

    // MARK: - Reference definitions

    /// The rename `rule` owes in a migration to `toVersion`, if any.
    private static func expectedRename(of rule: String, to toVersion: String) -> String? {
        let deprecation = SwiftLintDeprecations.deprecatedRules[rule]
        guard let target = SwiftLintDeprecations.renamedRules[rule] ?? deprecation?.replacement,
              target != rule else { return nil }
        if let renamedIn = deprecation?.deprecatedInVersion,
           SwiftLintDeprecations.isVersion(toVersion, lessThan: renamedIn) {
            return nil
        }
        return target
    }

    /// Whether `rule` was removed in a version after `from`, up to `to`.
    private static func removedBetween(_ rule: String, from: String, to target: String) -> Bool {
        guard let removedIn = SwiftLintDeprecations.removedRules[rule]?.removedInVersion else { return false }
        return SwiftLintDeprecations.isVersion(from, lessThan: removedIn)
            && !SwiftLintDeprecations.isVersion(target, lessThan: removedIn)
    }

    /// The rules the plan's new-rules note lists, or nil when it has no note.
    private static func noteRules(in plan: MigrationPlan) -> [String]? {
        for case .manualAction(let text) in plan.steps {
            // "New rules available: a, b. Consider enabling them." — rule ids hold no '.' or ':'
            guard let list = text.split(separator: ":").last?.split(separator: ".").first else { return [] }
            return list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    private static func renames(in plan: MigrationPlan) -> [String: String] {
        var renames: [String: String] = [:]
        for case .renameRule(let from, let newName) in plan.steps { renames[from] = newName }
        return renames
    }

    private static func removals(in plan: MigrationPlan) -> Set<String> {
        var removals: Set<String> = []
        for case .removeDeprecatedRule(let ruleId, _) in plan.steps { removals.insert(ruleId) }
        return removals
    }

    /// The rule each auto-applicable step acts on, one entry per step.
    private static func stepRules(in plan: MigrationPlan) -> [String] {
        plan.autoApplyableSteps.compactMap { step in
            switch step {
            case .renameRule(let from, _): return from
            case .removeDeprecatedRule(let ruleId, _): return ruleId
            case .updateParameter(let ruleId, _, _): return ruleId
            case .manualAction: return nil
            }
        }
    }

    // MARK: - Laws over the plan

    @Test("a configured rule is renamed exactly when its target exists in the target version")
    func renamesFollowTheTable() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let configured = Self.configuredIds(Self.config(for: spec))
            let toVersion = Self.versions[spec.toIndex]
            var expected: [String: String] = [:]
            for rule in configured {
                if let target = Self.expectedRename(of: rule, to: toVersion) { expected[rule] = target }
            }
            #expect(Self.renames(in: Self.plan(for: spec)) == expected)
        }
    }

    @Test("a configured rule is removed exactly when its removal falls in the window and it is not renamed")
    func removalsFollowTheWindow() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let plan = Self.plan(for: spec)
            let fromVersion = Self.versions[spec.fromIndex]
            let toVersion = Self.versions[spec.toIndex]
            let renamed = Self.renames(in: plan)
            let expected = Self.configuredIds(Self.config(for: spec)).filter {
                Self.removedBetween($0, from: fromVersion, to: toVersion) && renamed[$0] == nil
            }
            #expect(Self.removals(in: plan) == expected)
        }
    }

    @Test("no rule gets two auto-applicable steps")
    func atMostOneStepPerRule() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let rules = Self.stepRules(in: Self.plan(for: spec))
            #expect(rules.count == Set(rules).count)
        }
    }

    @Test("the new-rules note lists exactly the rules added in the range that the target still has")
    func newRulesNoteFollowsTheAdditions() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let target = Self.versions[spec.toIndex]
            let added = SwiftLintDeprecations.rulesAdded(from: Self.versions[spec.fromIndex], to: target)
                .filter { rule in
                    guard let removedIn = SwiftLintDeprecations.removedRules[rule]?.removedInVersion else {
                        return true
                    }
                    return SwiftLintDeprecations.isVersion(target, lessThan: removedIn)
                }
            let plan = Self.plan(for: spec)
            #expect(plan.manualSteps.count == (added.isEmpty ? 0 : 1))
            #expect(Self.noteRules(in: plan) == (added.isEmpty ? nil : added))
        }
    }

    // MARK: - Laws over applying it

    /// Proposed by swift-infer (`mutator-idempotence`) once the linter seeded
    /// `applyMigration` as a pure mutator: a second application changes nothing.
    @Test("applying a plan twice leaves what applying it once left")
    func applyingIsIdempotent() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let plan = Self.plan(for: spec)
            var once = Self.config(for: spec)
            Self.assistant.applyMigration(plan, to: &once)
            var twice = once
            Self.assistant.applyMigration(plan, to: &twice)
            #expect(once == twice)
        }
    }

    @Test("applying a plan replaces what it renames, drops what it removes, and touches nothing else")
    func applyingDoesWhatThePlanSays() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let plan = Self.plan(for: spec)
            let before = Self.config(for: spec)
            var after = before
            Self.assistant.applyMigration(plan, to: &after)

            let renamed = Self.renames(in: plan)
            let removed = Self.removals(in: plan)
            let expected = Set(Self.configuredIds(before).subtracting(removed).map { renamed[$0] ?? $0 })
            #expect(Self.configuredIds(after) == expected)
            // A list is absent or holds something — never present and empty.
            for list in [after.disabledRules, after.optInRules, after.analyzerRules, after.onlyRules] {
                #expect(list.map { !$0.isEmpty } ?? true)
            }
        }
    }

    // MARK: - The version gate, pinned

    /// The defect the rename law found: `identifier_name` arrived in 0.17.0.
    @Test("a rename is not offered before its target exists", arguments: [
        ("0.15.0", false), ("0.16.0", false), ("0.17.0", true), ("0.30.0", true)
    ])
    func renameWaitsForItsTarget(toVersion: String, renames: Bool) {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules = ["variable_name": RuleConfiguration(enabled: true)]
        let plan = Self.assistant.detectMigrations(config: config, fromVersion: "0.10.0", toVersion: toVersion)
        #expect((Self.renames(in: plan)["variable_name"] == "identifier_name") == renames)
    }

    /// A removed rule that is not also renamed, which no example test used when these laws
    /// were written.
    @Test("anyobject_protocol is removed exactly when the range crosses 0.57.0", arguments: [
        ("0.50.0", "0.57.0", true), ("0.50.0", "0.56.0", false), ("0.57.0", "0.60.0", false), ("0.56.0", "0.70.0", true)
    ])
    func anyObjectProtocolRemovalWindow(from: String, toVersion: String, removes: Bool) {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.optInRules = ["anyobject_protocol"]
        let plan = Self.assistant.detectMigrations(config: config, fromVersion: from, toVersion: toVersion)
        #expect(Self.removals(in: plan).contains("anyobject_protocol") == removes)
    }
}
