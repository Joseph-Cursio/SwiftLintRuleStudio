//
//  RuleDiffPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for `ConfigComparisonService.buildRuleDiff` — the per-rule
//  explanation the comparison view shows for a rule both configs set
//  differently. Mutation testing found that only its severity branch was
//  checked: deleting the enabled or the parameters message, or reporting
//  "enabled" for the disabled side, survived the example tests.
//
//  The laws state what each message owes, over pairs of configurations drawn
//  from tiny domains so that each field is equal about as often as it differs:
//
//      a message for exactly the fields that differ, in field order
//      the enabled message says which side is enabled and which is disabled
//      the severity message gives each side's severity, "default" when unset
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
        case enabled, severity, parameters
    }

    /// Which field a message is about, read from the shape `buildRuleDiff` gives it.
    private static func field(of message: String) -> Field {
        if message.hasPrefix("Severity:") { return .severity }
        if message == "Parameters differ" { return .parameters }
        return .enabled
    }

    private static func diff(_ first: RuleConfiguration, _ second: RuleConfiguration) -> RuleComparisonDiff {
        ConfigComparisonService().buildRuleDiff(
            ruleId: "rule", rc1: first, rc2: second,
            label1: firstLabel, label2: secondLabel
        )
    }

    // MARK: - Laws

    @Test("buildRuleDiff reports exactly the fields that differ, in field order")
    func reportsExactlyTheDifferingFields() async {
        await propertyCheck(
            input: Self.ruleConfigurationGenerator(), Self.ruleConfigurationGenerator()
        ) { first, second in
            var expected: [Field] = []
            if first.enabled != second.enabled { expected.append(.enabled) }
            if first.severity != second.severity { expected.append(.severity) }
            if first.parameters != second.parameters { expected.append(.parameters) }

            #expect(Self.diff(first, second).differences.map(Self.field) == expected)
        }
    }

    @Test("the enabled message says which side is enabled and which is disabled")
    func enabledMessageNamesEachSidesState() async {
        await propertyCheck(
            input: Self.ruleConfigurationGenerator(), Self.ruleConfigurationGenerator()
        ) { first, second in
            guard first.enabled != second.enabled else { return }
            let (onLabel, offLabel) = first.enabled
                ? (Self.firstLabel, Self.secondLabel)
                : (Self.secondLabel, Self.firstLabel)

            let message = Self.diff(first, second).differences.first { Self.field(of: $0) == .enabled }
            #expect(message?.contains("\(onLabel): enabled") == true)
            #expect(message?.contains("\(offLabel): disabled") == true)
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
            #expect(message?.contains("\(Self.firstLabel)=\(firstSeverity)") == true)
            #expect(message?.contains("\(Self.secondLabel)=\(secondSeverity)") == true)
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
