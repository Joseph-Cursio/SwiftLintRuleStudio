//
//  RuleListsPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for the rule lists (issue #83). The app wrote `only_rules` beside
//  `opt_in_rules`, which SwiftLint rejects, because three writers each routed rules
//  through the lists by hand. The laws pin what the shared routing promises instead:
//
//    A. The repair never leaves a conflict, never empties a non-empty `only_rules`, is
//       idempotent, and leaves a file SwiftLint already reads cleanly alone.
//    B. From any file SwiftLint accepts, turning a rule on or off leaves one it accepts —
//       or, for a disable that would empty `only_rules`, refuses and changes nothing.
//    C. Afterwards the resolver reports the rule exactly as it was set: the writers and
//       the toggles can't disagree.
//
//  The lists may name a rule by a deprecated alias, which SwiftLint reads as the rule.
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

/// One generated configuration and one action on it, as indices into the vocabulary so
/// the spec stays `Sendable` — `YAMLConfig` is main-actor-isolated.
private struct RuleListSpec: Sendable {
    let only: [Int]
    let optIn: [Int]
    let disabled: [Int]
    let analyzer: [Int]
    let target: Int
    let enables: Bool
}

@MainActor
@Suite("rule list property laws")
struct RuleListsPropertyLawTests {

    /// Two rules of each kind, so a list can hold a rule of the "wrong" kind too, and two
    /// with a deprecated alias.
    private static let vocabulary: [(id: String, kind: RuleListKind)] = [
        ("force_cast", .standard),
        ("line_length", .standard),
        ("empty_count", .optIn),
        ("first_where", .optIn),
        ("unused_import", .analyzer),
        ("explicit_self", .analyzer),
        ("identifier_name", .standard),
        ("shorthand_optional_binding", .optIn)
    ]

    /// What a list entry may say: a rule's id, or the alias SwiftLint reads as one of them.
    private static let listNames = vocabulary.map(\.id) + ["variable_name", "if_let_shadowing"]

    private static func specGenerator() -> Generator<RuleListSpec, some SendableSequenceType> {
        let target = Gen<Int>.int(in: 0 ... (vocabulary.count - 1))
        let list = Gen<Int>.int(in: 0 ... (listNames.count - 1)).array(of: 0...4)
        return zip(list, list, list, list, target, Gen<Bool>.bool)
            .map { RuleListSpec(only: $0, optIn: $1, disabled: $2, analyzer: $3, target: $4, enables: $5) }
    }

    private static func config(for spec: RuleListSpec) -> YAMLConfigurationEngine.YAMLConfig {
        func ids(_ indices: [Int]) -> [String]? {
            var seen: Set<String> = []
            let ids = indices.map { listNames[$0] }.filter { seen.insert($0).inserted }
            return ids.isEmpty ? nil : ids
        }
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.onlyRules = ids(spec.only)
        config.optInRules = ids(spec.optIn)
        config.disabledRules = ids(spec.disabled)
        config.analyzerRules = ids(spec.analyzer)
        return config
    }

    private static func rule(_ entry: (id: String, kind: RuleListKind)) -> Rule {
        Rule(
            id: entry.id,
            name: entry.id,
            description: "",
            category: .lint,
            isOptIn: entry.kind != .standard,
            isAnalyzer: entry.kind == .analyzer
        )
    }

    private static func kind(of ruleId: String) -> RuleListKind {
        vocabulary.first { $0.id == SwiftLintDeprecations.currentName(of: ruleId) }?.kind ?? .standard
    }

    // MARK: - A. The repair

    @Test("the repair never leaves a conflict and never empties a non-empty only_rules")
    func repairIsAccepted() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let config = Self.config(for: spec)
            let repaired = config.normalizedRuleLists()
            #expect(!repaired.hasOnlyRulesConflict)
            #expect(repaired.usesOnlyRules == config.usesOnlyRules)
            #expect(repaired.rulesInOnlyAndAnalyzerRules.isEmpty)
        }
    }

    @Test("the repair is idempotent")
    func repairIsIdempotent() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let repaired = Self.config(for: spec).normalizedRuleLists()
            #expect(repaired.normalizedRuleLists() == repaired)
        }
    }

    @Test("the repair leaves a file SwiftLint reads cleanly alone")
    func repairIsIdentityOnCleanFiles() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let config = Self.config(for: spec)
            guard ConfigRuleListsProblem(config) == nil else { return }
            #expect(config.normalizedRuleLists() == config)
        }
    }

    // MARK: - B and C. Turning a rule on or off

    @Test("from an accepted file, a toggle leaves an accepted file and the resolver agrees with it")
    func toggleKeepsTheFileAcceptedAndTheResolverInStep() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let start = Self.config(for: spec).normalizedRuleLists()
            let entry = Self.vocabulary[spec.target]
            var config = start

            if spec.enables {
                config.enableRule(entry.id, kind: entry.kind)
            } else {
                do {
                    try config.disableRule(entry.id, kind: entry.kind)
                } catch {
                    // Refused only to keep only_rules from emptying, and then untouched.
                    #expect(start.usesOnlyRules)
                    #expect(config == start)
                    return
                }
            }

            #expect(ConfigRuleListsProblem(config) == nil)
            #expect(config.usesOnlyRules == start.usesOnlyRules)
            #expect(RuleEnablementResolver.isRuleEnabled(Self.rule(entry), config: config) == spec.enables)
        }
    }

    @Test("a toggle never changes any other rule")
    func toggleTouchesOnlyItsRule() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let start = Self.config(for: spec).normalizedRuleLists()
            let entry = Self.vocabulary[spec.target]
            var config = start
            if spec.enables {
                config.enableRule(entry.id, kind: entry.kind)
            } else {
                guard (try? config.disableRule(entry.id, kind: entry.kind)) != nil else { return }
            }
            for other in Self.vocabulary where other.id != entry.id {
                let rule = Self.rule(other)
                #expect(
                    RuleEnablementResolver.isRuleEnabled(rule, config: config)
                        == RuleEnablementResolver.isRuleEnabled(rule, config: start)
                )
            }
        }
    }

    @Test("a batch disable is all or nothing, whatever order it comes in")
    func batchDisableIsAllOrNothing() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let start = Self.config(for: spec).normalizedRuleLists()
            guard start.usesOnlyRules else { return }
            let batch = (start.onlyRules ?? []) + [Self.vocabulary[spec.target].id]
            for order in [batch, batch.reversed()] {
                var config = start
                do {
                    try config.disableRules(order, kind: Self.kind(of:))
                    Issue.record("emptying only_rules should have been refused")
                } catch {
                    #expect(config == start)
                }
            }
        }
    }
}
