//
//  RuleDiffPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for `ConfigComparisonService.buildRuleDiff` — the per-rule
//  explanation the comparison view shows for a rule both configs set
//  differently. Mutation testing once found that only its severity branch was
//  checked; these laws pin every message.
//
//  The laws state what each message owes, over pairs of configurations drawn
//  from tiny domains so that each field is equal about as often as it differs:
//
//      a message for exactly the settings that differ: severity, then each parameter
//      `enabled` alone is no setting difference — whether a rule runs is the
//          comparison's on/off lists' job
//      the severity message gives each side's severity, "default" when unset
//      a parameter message names the side or sides that set it
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
@Suite("Rule diff property laws")
struct RuleDiffPropertyLawTests {

    private static let firstLabel = "Left"
    private static let secondLabel = "Right"

    // MARK: - Generators

    /// A rule configuration whose three fields each take one of two or three
    /// values, so two draws agree on a field often enough to exercise both the
    /// "same" and the "different" side of every comparison.
    static func ruleConfigurationGenerator() -> Generator<RuleConfiguration, some SendableSequenceType> {
        let enabled = Gen<Int>.int(in: 0...1).map { $0 == 1 }
        let severity = Gen<Int>.int(in: 0...2).map { [Severity?.none, .warning, .error][$0] }
        let parameters = Gen<Int>.int(in: 0...2).map { value -> [String: AnyCodable]? in
            value == 0 ? nil : ["warning": AnyCodable(value * 100)]
        }
        return zip(enabled, severity, parameters).map { enabled, severity, parameters in
            RuleConfiguration(enabled: enabled, severity: severity, parameters: parameters)
        }
    }

    // MARK: - Helpers

    private enum Field: Equatable {
        case severity
        case parameter(String)
    }

    /// Which setting a message is about, read from its `name:` prefix.
    private static func field(of message: String) -> Field {
        let name = String(message.prefix { $0 != ":" })
        return name == "severity" ? .severity : .parameter(name)
    }

    private static func diff(_ first: RuleConfiguration, _ second: RuleConfiguration) -> RuleComparisonDiff {
        ConfigComparisonService().buildRuleDiff(
            ruleId: "rule", rc1: first, rc2: second,
            label1: firstLabel, label2: secondLabel
        )
    }

    // MARK: - Laws

    @Test("buildRuleDiff reports exactly the settings that differ: severity, then each parameter")
    func reportsExactlyTheDifferingFields() async {
        await propertyCheck(
            input: Self.ruleConfigurationGenerator(), Self.ruleConfigurationGenerator()
        ) { first, second in
            var expected: [Field] = []
            if first.severity != second.severity { expected.append(.severity) }
            let keys = Set((first.parameters ?? [:]).keys).union((second.parameters ?? [:]).keys).sorted()
            for key in keys where first.parameters?[key] != second.parameters?[key] {
                expected.append(.parameter(key))
            }

            #expect(Self.diff(first, second).differences.map(Self.field) == expected)
        }
    }

    @Test("enabled alone is no setting difference")
    func enabledAloneIsNoDifference() async {
        await propertyCheck(input: Self.ruleConfigurationGenerator()) { config in
            var flipped = config
            flipped.enabled.toggle()
            #expect(Self.diff(config, flipped).differences.isEmpty)
        }
    }

    @Test("the severity message gives each side's severity, default when unset")
    func severityMessageNamesEachSidesSeverity() async {
        await propertyCheck(
            input: Self.ruleConfigurationGenerator(), Self.ruleConfigurationGenerator()
        ) { first, second in
            guard first.severity != second.severity else { return }
            let firstSeverity = first.severity?.rawValue ?? "default"
            let secondSeverity = second.severity?.rawValue ?? "default"

            let message = Self.diff(first, second).differences.first { Self.field(of: $0) == .severity }
            #expect(message?.contains("\(Self.firstLabel) \(firstSeverity)") == true)
            #expect(message?.contains("\(Self.secondLabel) \(secondSeverity)") == true)
        }
    }

    @Test("a parameter message names the side or sides that set it")
    func parameterMessageNamesItsSides() async {
        await propertyCheck(
            input: Self.ruleConfigurationGenerator(), Self.ruleConfigurationGenerator()
        ) { first, second in
            guard let message = Self.diff(first, second).differences.first(where: {
                Self.field(of: $0) == .parameter("warning")
            }) else { return }
            switch (first.parameters?["warning"], second.parameters?["warning"]) {
            case (_?, _?):
                #expect(message.contains(Self.firstLabel) && message.contains(Self.secondLabel))
            case (_?, nil):
                #expect(message.contains("only \(Self.firstLabel)"))
            case (nil, _?):
                #expect(message.contains("only \(Self.secondLabel)"))
            case (nil, nil):
                Issue.record("a message for a setting neither side has")
            }
        }
    }

    @Test("the diff carries the rule and both configurations through unchanged")
    func diffCarriesItsInputs() async {
        await propertyCheck(
            input: Self.ruleConfigurationGenerator(), Self.ruleConfigurationGenerator()
        ) { first, second in
            let diff = Self.diff(first, second)
            #expect(diff.id == "rule")
            #expect(diff.ruleId == "rule")
            #expect(diff.firstConfig == first)
            #expect(diff.secondConfig == second)
        }
    }
}
