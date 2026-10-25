//
//  RuleListsAliasSwiftLintAgreementTests.swift
//  SwiftLintInProcessBackendTests
//
//  Deprecated rule aliases in the rule lists, checked against the linked SwiftLint: it reads
//  `disabled_rules: [if_let_shadowing]` as turning `shorthand_optional_binding` off, so Core's
//  resolver and its enable/disable writes must too.
//

import Foundation
import SwiftLintRuleStudioCore
import Testing

/// One alias, the list it starts in, and whether the app turns its rule on or off.
struct RuleAliasToggle: Sendable, CustomTestStringConvertible {
    let alias: String
    let start: Start
    let enables: Bool

    enum Start: Sendable, CaseIterable {
        case disabledRules, optInRules, onlyRules
    }

    var rule: String { SwiftLintDeprecations.ruleAliases[alias] ?? alias }

    var yaml: String {
        switch start {
        case .disabledRules: "disabled_rules:\n  - \(alias)\n"
        case .optInRules: "opt_in_rules:\n  - \(alias)\n"
        case .onlyRules: "only_rules:\n  - \(alias)\n  - force_cast\n"
        }
    }

    var testDescription: String {
        "\(enables ? "enable" : "disable") \(rule) from \(start) [\(alias)]"
    }
}

/// Turning a rule on or off from the app, starting from a file that names it by an alias:
/// SwiftLint must then run it exactly when the app says so. Before, enabling
/// `identifier_name` left `variable_name` in `disabled_rules`, and the rule stayed off.
///
/// Core is built with `.defaultIsolation(MainActor.self)`, so the suite runs on the main actor.
@MainActor
@Suite("Rule aliases in the rule lists agree with the linked SwiftLint")
struct RuleListsAliasSwiftLintAgreementTests {
    private typealias Probe = SwiftLintConfigurationProbe

    typealias Toggle = RuleAliasToggle

    nonisolated static let toggles: [Toggle] = SwiftLintDeprecations.ruleAliases.keys.sorted().flatMap { alias in
        Toggle.Start.allCases.flatMap { start in
            [true, false].map { Toggle(alias: alias, start: start, enables: $0) }
        }
    }

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

    @Test("Every alias names a rule SwiftLint has registered")
    func aliasesNameRegisteredRules() {
        let registeredIds = Set(Self.registry.map(\.id))
        #expect(!SwiftLintDeprecations.ruleAliases.isEmpty)
        for (alias, rule) in SwiftLintDeprecations.ruleAliases {
            #expect(registeredIds.contains(rule), "\(alias) -> \(rule)")
            #expect(!registeredIds.contains(alias), "\(alias) is registered as a rule of its own")
        }
    }

    @Test("SwiftLint runs the rule exactly when the app turned it on", arguments: toggles)
    func toggleAgreesWithSwiftLint(_ toggle: Toggle) throws {
        let rule = try #require(Self.registry.first { $0.id == toggle.rule })
        var config = try YAMLConfigurationEngine.parse(toggle.yaml)
        if toggle.enables {
            config.enableRule(rule.id, kind: RuleListKind(rule))
        } else {
            try config.disableRule(rule.id, kind: RuleListKind(rule))
        }

        let yaml = try YAMLConfigurationEngine.serialize(config)
        let accepted = try #require(try Probe.load(yaml).accepted, "SwiftLint rejected:\n\(yaml)")
        #expect(accepted.enabledRuleIds.contains(rule.id) == toggle.enables, "\(yaml)")

        // The app reads the saved file the way SwiftLint does, every rule included.
        let reread = try YAMLConfigurationEngine.parse(yaml)
        let resolverOn = Set(
            Self.registry.filter { RuleEnablementResolver.isRuleEnabled($0, config: reread) }.map(\.id)
        )
        #expect(resolverOn == accepted.enabledRuleIds, "\(yaml)")

        // An alias already turning the rule off isn't joined by its current name.
        if toggle.start == .disabledRules, !toggle.enables, !rule.isOptIn {
            #expect(reread.disabledRules == [toggle.alias])
        }
    }
}

extension RuleListsAgreementCases {
    /// Configs naming rules by a deprecated alias, for the suite in
    /// `RuleListsSwiftLintAgreementTests`.
    static let aliasCases: [Case] = [
        Case(
            name: "Aliases in default mode: one opted in, one disabled",
            yaml: """
                opt_in_rules:
                  - if_let_shadowing
                disabled_rules:
                  - variable_name

                """,
            rejected: false,
            expected: .defaultMode(
                enabled: ["shorthand_optional_binding", "line_length"],
                disabled: ["identifier_name"]
            )
        ),
        Case(
            name: "An alias in only_rules runs its rule",
            yaml: """
                only_rules:
                  - variable_name
                  - force_cast

                """,
            rejected: false,
            expected: .exactly(["identifier_name", "force_cast"])
        ),
        Case(
            name: "An alias in disabled_rules beside only_rules takes its rule out of the repair",
            yaml: """
                only_rules:
                  - identifier_name
                  - force_cast
                disabled_rules:
                  - variable_name

                """,
            rejected: true,
            expected: .exactly(["force_cast"])
        ),
        Case(
            name: "An alias in opt_in_rules of a rule only_rules lists folds in once",
            yaml: """
                only_rules:
                  - shorthand_optional_binding
                opt_in_rules:
                  - if_let_shadowing
                  - empty_count

                """,
            rejected: true,
            expected: .exactly(["shorthand_optional_binding", "empty_count"])
        )
    ]
}
