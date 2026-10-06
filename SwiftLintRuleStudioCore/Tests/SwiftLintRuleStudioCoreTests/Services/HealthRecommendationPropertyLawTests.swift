//
//  HealthRecommendationPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for `ConfigurationHealthAnalyzer.generateRecommendations`, the
//  advice the health view shows under the score. Mutation testing found none of
//  it checked: every mutant in the file survived, deleting a recommendation
//  outright included, because the example tests only asked for *some*
//  recommendation and for priority order.
//
//  Each recommendation is a rule over the score breakdown, and the laws state
//  the rules as a decision table — what appears, exactly when, and with what
//  priority and action:
//
//      Configure Excluded Paths          path configuration < 60
//      Improve Category Coverage         category balance < 60
//      Enable More Rules                 rules coverage < 30
//      Consider Reducing Rules           rules coverage > 90
//      Enable Recommended Opt-In Rules   opt-in adoption < 50, and a recommended
//                                        rule is missing from opt_in_rules
//
//  The thresholds are product decisions, so they are written out once, in
//  `Threshold` below, rather than derived from the subject; changing one means
//  changing it there and in the subject. Generated scores lean toward each
//  threshold and its neighbours, where an off-by-one would show, and a
//  parameterized test checks those values on every run.
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

/// A generated breakdown and opt-in list, kept to primitives so it can cross
/// the generator boundary — `YAMLConfig` is main-actor-isolated.
private struct RecommendationSpec: Sendable {
    let rulesCoverage: Int
    let categoryBalance: Int
    let optInAdoption: Int
    let pathConfiguration: Int
    /// Indices into the recommended opt-in rules, or nil for all of them.
    let optInIndices: [Int]?
    /// Also list an opt-in rule that is not a recommended one.
    let listsOtherOptIn: Bool
}

@MainActor
@Suite("Health recommendation property laws")
struct HealthRecommendationPropertyLawTests {

    private enum Title {
        static let paths = "Configure Excluded Paths"
        static let balance = "Improve Category Coverage"
        static let moreRules = "Enable More Rules"
        static let fewerRules = "Consider Reducing Rules"
        static let optIn = "Enable Recommended Opt-In Rules"
    }

    /// The score each recommendation turns on at: below it, except `fewerRules`,
    /// which is above it.
    nonisolated private enum Threshold {
        static let paths = 60
        static let balance = 60
        static let moreRules = 30
        static let fewerRules = 90
        static let optIn = 50
    }

    /// Each threshold, one either side, and the ends of the range.
    nonisolated private static let thresholdNeighbourhood: [Int] = {
        let thresholds = [
            Threshold.paths, Threshold.balance, Threshold.moreRules, Threshold.fewerRules, Threshold.optIn
        ]
        return Set([0, 100] + thresholds.flatMap { [$0 - 1, $0, $0 + 1] }).sorted()
    }()

    private static let recommendedOptInRules = ConfigurationHealthAnalyzer().recommendedOptInRules.sorted()

    // MARK: - Generators

    private static func scoreGenerator() -> Generator<Int, some SendableSequenceType> {
        let near = thresholdNeighbourhood
        return Gen.frequency(
            (3.0, Gen<Int>.int(in: 0 ... (near.count - 1)).map { near[$0] }),
            (1.0, Gen<Int>.int(in: 0...100))
        )
    }

    private static func specGenerator() -> Generator<RecommendationSpec, some SendableSequenceType> {
        let count = recommendedOptInRules.count
        // A quarter of the time every recommended rule is listed, so the
        // "nothing missing" side of the opt-in rule comes up as often as it needs to.
        let optIn = Gen.frequency(
            (3.0, Gen<Int>.int(in: 0 ... (count - 1)).array(of: 0 ... count).map { Optional($0) }),
            (1.0, Gen<Bool>.bool.map { _ -> [Int]? in nil })
        )
        return zip(
            scoreGenerator(), scoreGenerator(), scoreGenerator(), scoreGenerator(),
            optIn, Gen<Bool>.bool
        ).map { coverage, balance, adoption, path, optIn, other in
            RecommendationSpec(
                rulesCoverage: coverage,
                categoryBalance: balance,
                optInAdoption: adoption,
                pathConfiguration: path,
                optInIndices: optIn,
                listsOtherOptIn: other
            )
        }
    }

    // MARK: - Construction

    private static func optInRules(from spec: RecommendationSpec) -> [String] {
        var names = spec.optInIndices.map { $0.map { recommendedOptInRules[$0] } } ?? recommendedOptInRules
        if spec.listsOtherOptIn { names.append("explicit_self") }
        return Array(Set(names)).sorted()
    }

    private static func recommendations(for spec: RecommendationSpec) -> [HealthRecommendation] {
        var config = YAMLConfigurationEngine.YAMLConfig()
        let optIn = optInRules(from: spec)
        config.optInRules = optIn.isEmpty ? nil : optIn
        let breakdown = ConfigHealthReport.ScoreBreakdown(
            rulesCoverage: spec.rulesCoverage,
            categoryBalance: spec.categoryBalance,
            optInAdoption: spec.optInAdoption,
            noDeprecatedRules: 100,
            pathConfiguration: spec.pathConfiguration
        )
        return ConfigurationHealthAnalyzer().generateRecommendations(
            config: config, knownRules: [], breakdown: breakdown
        )
    }

    // MARK: - The decision table

    /// Which recommendations appear, and how many times each, for `spec`.
    private static func expectDecisionTable(
        for spec: RecommendationSpec,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let titles = recommendations(for: spec).map(\.title)
        let count = { (title: String) in titles.filter { $0 == title }.count }
        let missing = Set(recommendedOptInRules).subtracting(optInRules(from: spec))

        #expect(
            count(Title.paths) == (spec.pathConfiguration < Threshold.paths ? 1 : 0),
            sourceLocation: sourceLocation
        )
        #expect(
            count(Title.balance) == (spec.categoryBalance < Threshold.balance ? 1 : 0),
            sourceLocation: sourceLocation
        )
        #expect(
            count(Title.moreRules) == (spec.rulesCoverage < Threshold.moreRules ? 1 : 0),
            sourceLocation: sourceLocation
        )
        #expect(
            count(Title.fewerRules) == (spec.rulesCoverage > Threshold.fewerRules ? 1 : 0),
            sourceLocation: sourceLocation
        )
        #expect(
            count(Title.optIn) == (spec.optInAdoption < Threshold.optIn && !missing.isEmpty ? 1 : 0),
            sourceLocation: sourceLocation
        )
    }

    // MARK: - Laws

    @Test("each recommendation appears exactly when its rule says, and at most once")
    func recommendationsFollowTheDecisionTable() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            Self.expectDecisionTable(for: spec)
        }
    }

    /// The generated check reaches a given threshold in about one sample in
    /// twenty, so an off-by-one there would slip past an unlucky run. Every
    /// threshold and its neighbours are checked here on every run, for each
    /// score at once, with every recommended rule missing so the opt-in rule
    /// turns on adoption alone — and again with none missing.
    @Test(
        "the decision table holds at every threshold and either side of it",
        arguments: Self.thresholdNeighbourhood
    )
    func decisionTableHoldsAtTheThresholds(score: Int) {
        for optInIndices in [[], nil] as [[Int]?] {
            Self.expectDecisionTable(for: RecommendationSpec(
                rulesCoverage: score,
                categoryBalance: score,
                optInAdoption: score,
                pathConfiguration: score,
                optInIndices: optInIndices,
                listsOtherOptIn: false
            ))
        }
    }

    @Test("the opt-in recommendation names up to three recommended rules, all of them missing")
    func optInRecommendationNamesMissingRules() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let missing = Set(Self.recommendedOptInRules).subtracting(Self.optInRules(from: spec))
            guard let recommendation = Self.recommendations(for: spec).first(where: { $0.title == Title.optIn })
            else { return }

            // Stop at a wrong prefix: parsing past it would report a misleading
            // second failure about which rules were named.
            let prefix = "Consider enabling: "
            try #require(recommendation.description.hasPrefix(prefix))
            let named = recommendation.description.dropFirst(prefix.count).components(separatedBy: ", ")
            #expect(Set(named).count == named.count)
            #expect(Set(named).isSubset(of: missing))
            #expect(named.count == min(3, missing.count))
        }
    }

    @Test("every recommendation is one of the five, with its priority and action")
    func recommendationsCarryTheirPriorityAndAction() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            for recommendation in Self.recommendations(for: spec) {
                let action = recommendation.actionType
                switch recommendation.title {
                case Title.paths:
                    #expect(recommendation.priority == .high)
                    #expect(recommendation.presetId == nil)
                    guard case .configureExcludes = action else { Issue.record("\(action)"); continue }
                case Title.balance, Title.fewerRules:
                    #expect(recommendation.priority == .low)
                    #expect(recommendation.presetId == nil)
                    guard case .general = action else { Issue.record("\(action)"); continue }
                case Title.moreRules:
                    #expect(recommendation.priority == .high)
                    #expect(recommendation.presetId == "code_style")
                    guard case .enablePreset("code_style") = action else { Issue.record("\(action)"); continue }
                case Title.optIn:
                    #expect(recommendation.priority == .medium)
                    #expect(recommendation.presetId == "performance")
                    guard case .enablePreset("performance") = action else { Issue.record("\(action)"); continue }
                default:
                    Issue.record("Unexpected recommendation: \(recommendation.title)")
                }
            }
        }
    }
}
