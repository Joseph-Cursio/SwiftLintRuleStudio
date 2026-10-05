//
//  HealthScorePropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for `ConfigurationHealthAnalyzer.analyze(config:knownRules:)`.
//  Mutation testing found the score's arithmetic unchecked: dividing where it
//  multiplies, or subtracting a weighted term instead of adding it, survived
//  the example tests, as did inverting the include/exclude bonuses. The laws
//  state what a score owes, whatever the configuration:
//
//      every component, and the score, lies in 0...100, and the grade is the score's
//      the score is the weighted mean of the breakdown, with the weights it shows
//      listing an opt-in rule nobody enabled in disabled_rules changes nothing
//      rules coverage is full exactly when at least half the known rules are on
//      included paths, and excluding a common directory, raise the path score
//
//  Not stated: `noDeprecatedRules`. Its `deprecatedRules` set is empty, so the
//  component is 100 for every configuration and its arithmetic never runs.
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

/// A generated configuration and rule catalogue, kept to primitives so it can
/// cross the generator boundary — `YAMLConfig` is main-actor-isolated.
private struct HealthSpec: Sendable {
    /// Per pool rule: 0 = not a known rule, n = known, in category n - 1.
    let ruleSlots: [Int]
    let optInIndices: [Int]
    let disabledIndices: [Int]
    let configuredIndices: [Int]
    let configuredEnabled: Bool
    /// 0 = none, 1 = empty, 2 = an uncommon directory, 3 = that and a common one.
    let excludedKind: Int
    let setsIncluded: Bool
}

@MainActor
@Suite("Health score property laws")
struct HealthScorePropertyLawTests {

    /// Six rules, three of them opt-in, so a catalogue drawn from them has both
    /// kinds and the lists below name the same rules often.
    nonisolated private static let rulePool: [(id: String, isOptIn: Bool)] = [
        ("force_cast", false), ("line_length", false), ("todo", false),
        ("first_where", true), ("empty_count", true), ("explicit_self", true)
    ]

    /// Opt-in names a config may list: the pool's opt-in rules, two of them
    /// recommended, plus a recommended rule no catalogue declares.
    nonisolated private static let optInNames = ["first_where", "empty_count", "explicit_self", "reduce_into"]

    // MARK: - Generators

    private static func specGenerator() -> Generator<HealthSpec, some SendableSequenceType> {
        let poolIndex = Gen<Int>.int(in: 0 ... (rulePool.count - 1))
        return zip(
            Gen<Int>.int(in: 0 ... RuleCategory.allCases.count).array(of: rulePool.count ... rulePool.count),
            Gen<Int>.int(in: 0 ... (optInNames.count - 1)).array(of: 0...3),
            poolIndex.array(of: 0...3),
            poolIndex.array(of: 0...2),
            Gen<Bool>.bool,
            Gen<Int>.int(in: 0...3),
            Gen<Bool>.bool
        ).map { slots, optIn, disabled, configured, enabled, excluded, included in
            HealthSpec(
                ruleSlots: slots,
                optInIndices: optIn,
                disabledIndices: disabled,
                configuredIndices: configured,
                configuredEnabled: enabled,
                excludedKind: excluded,
                setsIncluded: included
            )
        }
    }

    // MARK: - Construction

    private static func knownRules(from spec: HealthSpec) -> [Rule] {
        zip(rulePool, spec.ruleSlots).compactMap { entry, slot in
            guard slot > 0 else { return nil }
            return Rule(
                id: entry.id, name: entry.id, description: "",
                category: RuleCategory.allCases[slot - 1], isOptIn: entry.isOptIn
            )
        }
    }

    private static func config(from spec: HealthSpec) -> YAMLConfigurationEngine.YAMLConfig {
        let names = { (list: [String]) -> [String]? in
            list.isEmpty ? nil : Array(Set(list)).sorted()
        }
        var config = YAMLConfigurationEngine.YAMLConfig()
        for index in spec.configuredIndices {
            config.rules[rulePool[index].id] = RuleConfiguration(enabled: spec.configuredEnabled)
        }
        config.optInRules = names(spec.optInIndices.map { optInNames[$0] })
        config.disabledRules = names(spec.disabledIndices.map { rulePool[$0].id })
        config.excluded = [nil, [], ["Sources/Generated"], ["Sources/Generated", "Pods"]][spec.excludedKind]
        config.included = spec.setsIncluded ? ["Sources"] : nil
        return config
    }

    private static func analyze(
        _ config: YAMLConfigurationEngine.YAMLConfig,
        _ knownRules: [Rule]
    ) -> ConfigHealthReport {
        ConfigurationHealthAnalyzer().analyze(config: config, knownRules: knownRules)
    }

    // MARK: - Laws

    @Test("every component and the score lie in 0...100, and the grade is the score's")
    func scoresAreBounded() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let report = Self.analyze(Self.config(from: spec), Self.knownRules(from: spec))
            for detail in report.breakdown.details {
                #expect((0...100).contains(detail.score), "\(detail.name) = \(detail.score)")
            }
            #expect((0...100).contains(report.score))
            #expect(report.grade == HealthGrade.from(score: report.score))
        }
    }

    @Test("the score is the weighted mean of the breakdown, with the weights it shows")
    func scoreIsTheWeightedMeanOfTheBreakdown() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let report = Self.analyze(Self.config(from: spec), Self.knownRules(from: spec))
            let details = report.breakdown.details
            #expect(details.map(\.weight).reduce(0, +) == 100)

            // Σ score × weight is exact in integers; the score is that over 100,
            // rounded. Allow either neighbour at an exact half, where the
            // analyzer's floating-point weights may round the other way.
            let weightedSum = details.map { $0.score * $0.weight }.reduce(0, +)
            #expect(abs(report.score * 100 - weightedSum) <= 50)
        }
    }

    @Test("listing an opt-in rule nobody enabled in disabled_rules changes nothing")
    func disablingAnInactiveOptInRuleIsANoOp() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let known = Self.knownRules(from: spec)
            var config = Self.config(from: spec)
            let mentioned = Set(config.optInRules ?? [])
                .union(config.disabledRules ?? [])
                .union(config.rules.keys)
            guard let inactive = known.first(where: { $0.isOptIn && !mentioned.contains($0.id) }) else { return }

            let before = Self.analyze(config, known)
            config.disabledRules = (config.disabledRules ?? []) + [inactive.id]
            let after = Self.analyze(config, known)

            #expect(after.breakdown.details.map(\.score) == before.breakdown.details.map(\.score))
            #expect(after.score == before.score)
        }
    }

    @Test("rules coverage is full exactly when at least half the known rules are on")
    func rulesCoverageIsFullFromHalfEnabled() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let known = Self.knownRules(from: spec)
            guard !known.isEmpty else { return }

            // Keep to configs where "on" is unambiguous: no explicit rule
            // entries, opt-ins only for opt-in rules the catalogue knows, and no
            // rule both opted in and disabled. ConfigurationValidator rejects
            // that last case, and SwiftLint (disabled wins) and this analyzer
            // (opt-in wins) disagree on it, so the law takes no side.
            var config = Self.config(from: spec)
            config.rules = [:]
            let disabled = Set(config.disabledRules ?? [])
            let knownOptIn = Set(known.filter(\.isOptIn).map(\.id))
            let optIn = Set(config.optInRules ?? []).intersection(knownOptIn).subtracting(disabled)
            config.optInRules = optIn.isEmpty ? nil : optIn.sorted()

            let enabled = known.filter { rule in
                rule.isOptIn ? optIn.contains(rule.id) : !disabled.contains(rule.id)
            }.count
            let coverage = Self.analyze(config, known).breakdown.rulesCoverage
            #expect((coverage == 100) == (2 * enabled >= known.count), "\(enabled) of \(known.count) on")
        }
    }

    @Test("included paths raise the path score; an empty list is no list")
    func includedPathsRaiseThePathScore() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            var config = Self.config(from: spec)
            config.included = nil
            let without = Self.analyze(config, []).breakdown.pathConfiguration
            config.included = []
            let withEmpty = Self.analyze(config, []).breakdown.pathConfiguration
            config.included = ["Sources"]
            let withPaths = Self.analyze(config, []).breakdown.pathConfiguration

            #expect(withEmpty == without)
            #expect(withPaths > without)
        }
    }

    @Test("excluding a common directory scores higher than excluding only others")
    func excludingACommonDirectoryRaisesThePathScore() async {
        let commonDirectories = ["Pods", "Carthage", "vendor", "build", ".build"]
        await propertyCheck(
            input: Gen<Int>.int(in: 0 ... (commonDirectories.count - 1)), Gen<Bool>.bool
        ) { commonIndex, setsIncluded in
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.included = setsIncluded ? ["Sources"] : nil
            config.excluded = ["Sources/Generated"]
            let uncommonOnly = Self.analyze(config, []).breakdown.pathConfiguration
            config.excluded = ["Sources/Generated", commonDirectories[commonIndex]]
            let withCommon = Self.analyze(config, []).breakdown.pathConfiguration

            #expect(withCommon > uncommonOnly)
        }
    }
}
