//
//  RuleListsSwiftLintAgreementTests.swift
//  SwiftLintInProcessBackendTests
//
//  Issue #83, end to end: Core's reading and repair of a config's rule lists, checked
//  against the SwiftLint the app links rather than against Core's own model of it.
//

import Foundation
import SwiftLintRuleStudioCore
import Testing

/// The configs the suite checks, each with what SwiftLint should make of it.
enum RuleListsAgreementCases {
    /// The rules SwiftLint runs once the file is repaired. Pins each case to known ids, so a
    /// list both sides misread the same way can't make the comparisons agree vacuously.
    enum ExpectedRules: Sendable {
        /// Only mode: exactly these.
        case exactly(Set<String>)
        /// Default mode: at least these on, and these off.
        case defaultMode(enabled: Set<String>, disabled: Set<String>)

        var ids: Set<String> {
            switch self {
            case let .exactly(ids): ids
            case let .defaultMode(enabled, disabled): enabled.union(disabled)
            }
        }
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let yaml: String
        /// Whether SwiftLint rejects the file as written.
        let rejected: Bool
        let expected: ExpectedRules
        var included: [String] = []
        var excluded: [String] = []
        var strict = false
        /// Rule settings the repaired file must still carry: a fragment of each rule's
        /// settings as SwiftLint reads them.
        var settings: [String: String] = [:]

        var testDescription: String { name }
    }

    static let all: [Case] = [
        Case(
            name: "#83 (trimmed): rules duplicated across only_rules, opt_in_rules and analyzer_rules",
            yaml: """
                excluded:
                  - .build
                included:
                  - Sources
                  - Tests
                # If true, SwiftLint will treat all warnings as errors.
                strict: true
                only_rules:
                  - trailing_comma
                  - vertical_whitespace
                  - non_overridable_class_declaration
                  - period_spacing
                  - capture_variable
                  - array_init
                  - explicit_self
                  - colon
                  - unused_import
                  - typesafe_array_init
                  - unused_declaration
                  - empty_count
                  - force_cast
                  - force_unwrapping
                  - line_length
                trailing_comma:
                  mandatory_comma: true
                opt_in_rules:
                  - non_overridable_class_declaration
                  - period_spacing
                  - array_init
                  - empty_count
                  - force_unwrapping
                analyzer_rules:
                  - capture_variable
                  - explicit_self
                  - unused_import
                  - typesafe_array_init
                  - unused_declaration

                """,
            rejected: true,
            expected: .exactly([
                "trailing_comma", "vertical_whitespace", "non_overridable_class_declaration",
                "period_spacing", "capture_variable", "array_init", "explicit_self", "colon",
                "unused_import", "typesafe_array_init", "unused_declaration", "empty_count",
                "force_cast", "force_unwrapping", "line_length"
            ]),
            included: ["Sources", "Tests"],
            excluded: [".build"],
            strict: true,
            settings: ["trailing_comma": "mandatory_comma: true"]
        ),
        Case(
            name: "Old Rule Browser output: opt-in rule only in opt_in_rules, disabled rule left in only_rules",
            yaml: """
                only_rules:
                  - force_cast
                  - todo
                  - trailing_comma
                opt_in_rules:
                  - empty_count
                disabled_rules:
                  - todo

                """,
            rejected: true,
            expected: .exactly(["force_cast", "trailing_comma", "empty_count"])
        ),
        Case(
            name: "only_rules beside analyzer_rules, no overlap: accepted, and SwiftLint runs both",
            yaml: """
                only_rules:
                  - force_cast
                  - empty_count
                analyzer_rules:
                  - unused_import

                """,
            rejected: false,
            expected: .exactly(["force_cast", "empty_count", "unused_import"])
        ),
        Case(
            name: "An empty only_rules is default mode, so opt_in_rules and disabled_rules are accepted",
            yaml: """
                included:
                  - Sources
                only_rules: []
                opt_in_rules:
                  - empty_count
                  - force_unwrapping
                disabled_rules:
                  - todo
                  - force_cast
                analyzer_rules:
                  - unused_import
                line_length:
                  warning: 150
                closure_body_length:
                  warning: 50

                """,
            rejected: false,
            expected: .defaultMode(
                enabled: ["empty_count", "force_unwrapping", "unused_import", "line_length", "trailing_comma"],
                disabled: ["todo", "force_cast", "explicit_self", "closure_body_length"]
            ),
            included: ["Sources"],
            settings: ["line_length": "warning: 150"]
        ),
        Case(
            name: "only_rules beside the deprecated enabled_rules alias is rejected",
            yaml: """
                only_rules:
                  - force_cast
                enabled_rules:
                  - empty_count

                """,
            rejected: true,
            expected: .exactly(["force_cast", "empty_count"])
        ),
        Case(
            name: "A single-string only_rules is a one-rule list",
            yaml: "only_rules: force_cast\n",
            rejected: false,
            expected: .exactly(["force_cast"])
        ),
        Case(
            name: "Single-string only_rules beside a single-string opt_in_rules is rejected",
            yaml: "only_rules: force_cast\nopt_in_rules: empty_count\n",
            rejected: true,
            expected: .exactly(["force_cast", "empty_count"])
        ),
        Case(
            name: "An analyzer rule under opt_in_rules beside only_rules folds into only_rules",
            yaml: """
                only_rules:
                  - force_cast
                opt_in_rules:
                  - unused_import

                """,
            rejected: true,
            expected: .exactly(["force_cast", "unused_import"])
        ),
        Case(
            name: "A disabled analyzer rule leaves analyzer_rules too",
            yaml: """
                only_rules:
                  - force_cast
                disabled_rules:
                  - unused_import
                analyzer_rules:
                  - unused_import
                  - explicit_self

                """,
            rejected: true,
            expected: .exactly(["force_cast", "explicit_self"])
        ),
        Case(
            name: "An only_rules whose entries are all commented out is null: default mode, accepted",
            yaml: """
                only_rules:
                  # - force_cast
                disabled_rules:
                  - todo

                """,
            rejected: false,
            expected: .defaultMode(enabled: ["force_cast", "line_length"], disabled: ["todo", "empty_count"])
        ),
        Case(
            name: "A null opt_in_rules beside only_rules is no conflict",
            yaml: """
                only_rules:
                  - force_cast
                opt_in_rules: ~
                disabled_rules:

                """,
            rejected: false,
            expected: .exactly(["force_cast"])
        ),
        Case(
            name: "Every only_rules entry disabled: the repair keeps only_rules rather than empty it",
            yaml: """
                only_rules:
                  - todo
                disabled_rules:
                  - todo

                """,
            rejected: true,
            expected: .exactly(["todo"])
        )
    ] + aliasCases
}

/// Core answers three questions about a `.swiftlint.yml`'s rule lists without asking
/// SwiftLint: will SwiftLint reject the file (`hasOnlyRulesConflict`), how to rewrite it so
/// SwiftLint accepts it (`normalizedRuleLists()`), and which rules it turns on
/// (`RuleEnablementResolver`). Issue #83 was the app saving `only_rules` beside
/// `opt_in_rules`, which SwiftLint rejects wholesale — `included` and `excluded` with it.
/// Each test puts one of Core's answers next to SwiftLint's own, through
/// ``SwiftLintConfigurationProbe``.
///
/// Default-mode cases steer clear of resolver divergences that predate #83 and have nothing
/// to do with `only_rules`: a rule in both `opt_in_rules` and `disabled_rules`, `all`, an
/// analyzer rule under `opt_in_rules`, and `enabled: false` mappings.
///
/// Core is built with `.defaultIsolation(MainActor.self)`, so the suite runs on the main actor.
@MainActor
@Suite("Rule lists agree with the linked SwiftLint (issue #83)")
struct RuleListsSwiftLintAgreementTests {
    private typealias Config = YAMLConfigurationEngine.YAMLConfig
    private typealias Probe = SwiftLintConfigurationProbe
    typealias Case = RuleListsAgreementCases.Case

    /// What SwiftLint says when it rejects `only_rules` beside `opt_in_rules` or
    /// `disabled_rules`. The probe reports the error as described, quotes escaped, so this
    /// matches the words around them.
    private static let rulesModeRejection = ["cannot be used in combination with", "only_rules"]

    /// SwiftLint's registered rules as the app models them, each classified by the protocols
    /// its type conforms to. Analyzer rules are opt-in as well, as `swiftlint rules` reports them.
    private static let registry: [Rule] = Probe.registeredRules.map {
        Rule(
            id: $0.id,
            name: $0.id,
            description: "",
            category: .lint,
            isOptIn: $0.isOptIn,
            isAnalyzer: $0.isAnalyzer
        )
    }

    // MARK: - Tests

    @Test("The comparison draws on standard, opt-in and analyzer rules")
    func registryCoversEveryKind() {
        let analyzerIds = Set(Self.registry.filter(\.isAnalyzer).map(\.id))
        let optInIds = Set(Self.registry.filter(\.isOptIn).map(\.id))
        #expect(!analyzerIds.isEmpty)
        #expect(optInIds.count > analyzerIds.count)
        #expect(optInIds.count < Self.registry.count)
        #expect(analyzerIds.isSubset(of: optInIds), "AnalyzerRule refines OptInRule")
    }

    @Test(
        "hasOnlyRulesConflict is true exactly when SwiftLint rejects the file",
        arguments: RuleListsAgreementCases.all
    )
    func conflictMatchesSwiftLint(_ testCase: Case) throws {
        let config = try YAMLConfigurationEngine.parse(testCase.yaml)
        let rejection = try Probe.load(testCase.yaml).rejectionReason

        #expect((rejection != nil) == testCase.rejected, "SwiftLint: \(rejection ?? "accepted")")
        #expect(config.hasOnlyRulesConflict == (rejection != nil))
        if let rejection {
            let isRulesMode = Self.rulesModeRejection.allSatisfy { rejection.contains($0) }
            #expect(isRulesMode, "rejected for another reason: \(rejection)")
        }
    }

    @Test(
        "SwiftLint accepts the repaired file, with included, excluded and rule settings intact",
        arguments: RuleListsAgreementCases.all
    )
    func repairIsAccepted(_ testCase: Case) throws {
        let repairedYAML = try YAMLConfigurationEngine.serialize(
            YAMLConfigurationEngine.parse(testCase.yaml).normalizedRuleLists()
        )
        let outcome = try Probe.load(repairedYAML)
        let accepted = try #require(
            outcome.accepted,
            "SwiftLint rejected the repair: \(outcome.rejectionReason ?? "")\n\(repairedYAML)"
        )

        #expect(accepted.included == testCase.included)
        #expect(accepted.excluded == testCase.excluded)
        #expect(accepted.strict == testCase.strict)
        for (ruleId, fragment) in testCase.settings {
            let settings = accepted.settings[ruleId]
            #expect(settings?.contains(fragment) == true, "\(ruleId): \(settings ?? "not enabled")")
        }
        let reread = try YAMLConfigurationEngine.parse(repairedYAML)
        #expect(ConfigRuleListsProblem(reread) == nil, "\(repairedYAML)")
    }

    @Test(
        "SwiftLint runs exactly the rules the resolver reports on",
        arguments: RuleListsAgreementCases.all
    )
    func resolverMatchesSwiftLint(_ testCase: Case) throws {
        let config = try YAMLConfigurationEngine.parse(testCase.yaml)
        let repairedYAML = try YAMLConfigurationEngine.serialize(config.normalizedRuleLists())
        let repaired = try #require(try Probe.load(repairedYAML).accepted, "\(repairedYAML)").enabledRuleIds

        let registeredIds = Set(Self.registry.map(\.id))
        #expect(testCase.expected.ids.isSubset(of: registeredIds), "the case names unregistered ids")
        switch testCase.expected {
        case let .exactly(ids):
            #expect(repaired == ids)
        case let .defaultMode(enabled, disabled):
            #expect(enabled.subtracting(repaired).isEmpty, "expected on: \(enabled.subtracting(repaired).sorted())")
            #expect(disabled.isDisjoint(with: repaired), "expected off: \(disabled.intersection(repaired).sorted())")
        }

        // The toggles for the file as loaded: the resolver reads it as the repair will write it.
        expectAgreement(
            resolver: enabledIds(under: config),
            swiftLint: repaired,
            "as written, against SwiftLint on the repair"
        )
        // The repaired file, read back after a save.
        let reread = try YAMLConfigurationEngine.parse(repairedYAML)
        expectAgreement(resolver: enabledIds(under: reread), swiftLint: repaired, "repaired, read back")
        // A file SwiftLint accepts as written must also match SwiftLint's reading of that file.
        if let asWritten = try Probe.load(testCase.yaml).accepted {
            expectAgreement(resolver: enabledIds(under: config), swiftLint: asWritten.enabledRuleIds, "as written")
        }
    }

    // MARK: - Helpers

    private func enabledIds(under config: Config) -> Set<String> {
        Set(Self.registry.filter { RuleEnablementResolver.isRuleEnabled($0, config: config) }.map(\.id))
    }

    private func expectAgreement(
        resolver: Set<String>,
        swiftLint: Set<String>,
        _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            resolver.subtracting(swiftLint).isEmpty,
            "\(label): the resolver says on, SwiftLint doesn't run: \(resolver.subtracting(swiftLint).sorted())",
            sourceLocation: sourceLocation
        )
        #expect(
            swiftLint.subtracting(resolver).isEmpty,
            "\(label): SwiftLint runs, the resolver says off: \(swiftLint.subtracting(resolver).sorted())",
            sourceLocation: sourceLocation
        )
    }
}
