//
//  ResolvedConfigurationAliasAgreementTests.swift
//  SwiftLintInProcessBackendTests
//
//  Deprecated rule aliases across a parent and a child config, checked against the linked
//  SwiftLint: it maps each config's rule lists through the rules' aliases before it merges
//  them, so Core's `ResolvedConfigurationEngine`, which the Config Map and its verification
//  read, must too (#101).
//

import Foundation
import SwiftLintRuleStudioCore
import Testing

/// A root config, a config in its `Sub` folder, and what SwiftLint does with one rule there.
struct NestedAliasCase: Sendable, CustomTestStringConvertible {
    let name: String
    let parent: String
    let child: String
    let rule: String
    let runsInSub: Bool

    var testDescription: String { name }
}

/// Before, a child's `disabled_rules: [if_let_shadowing]` left the parent's opted-in
/// `shorthand_optional_binding` on in the resolved configuration, beside a second, disabled row
/// for the alias, while SwiftLint turned the rule off.
///
/// Core is built with `.defaultIsolation(MainActor.self)`, so the suite runs on the main actor.
@MainActor
@Suite("Rule aliases across nested configs agree with the linked SwiftLint")
struct ResolvedConfigurationAliasAgreementTests {
    private typealias Probe = SwiftLintConfigurationProbe

    typealias Case = NestedAliasCase

    nonisolated static let cases: [Case] = [
        Case(
            name: "A child disables, by its alias, a rule its parent opts in",
            parent: "opt_in_rules:\n  - shorthand_optional_binding\n",
            child: "disabled_rules:\n  - if_let_shadowing\n",
            rule: "shorthand_optional_binding",
            runsInSub: false
        ),
        Case(
            name: "A child disables a rule its parent opts in by its alias",
            parent: "opt_in_rules:\n  - if_let_shadowing\n",
            child: "disabled_rules:\n  - shorthand_optional_binding\n",
            rule: "shorthand_optional_binding",
            runsInSub: false
        ),
        Case(
            name: "A child turns back on a rule its parent disables by its alias",
            parent: "disabled_rules:\n  - variable_name\n",
            child: "opt_in_rules:\n  - identifier_name\n",
            rule: "identifier_name",
            runsInSub: true
        ),
        Case(
            name: "A child turns back on, by its alias, a rule its parent disables",
            parent: "disabled_rules:\n  - identifier_name\n",
            child: "opt_in_rules:\n  - variable_name\n",
            rule: "identifier_name",
            runsInSub: true
        ),
        Case(
            name: "A child names a rule its parent opts in under both lists, once by its alias",
            parent: "opt_in_rules:\n  - redundant_self\n",
            child: "disabled_rules:\n  - redundant_self_in_closure\nopt_in_rules:\n  - redundant_self\n",
            rule: "redundant_self",
            runsInSub: false
        ),
        Case(
            name: "A child's only_rules runs, by its alias, a rule its parent disables",
            parent: "disabled_rules:\n  - function_name_whitespace\n",
            child: "only_rules:\n  - operator_whitespace\n  - force_cast\n",
            rule: "function_name_whitespace",
            runsInSub: true
        )
    ]

    /// One probe per rule SwiftLint has registered, for the harness to ask about.
    private static let probes: [RuleProbe] = Probe.registeredRules.map {
        RuleProbe(ruleIdentifier: $0.id, isOptIn: $0.isOptIn, triggeringSource: "")
    }

    @Test("The resolved configuration runs in the child's folder exactly what SwiftLint runs", arguments: cases)
    func resolvedConfigurationAgreesWithSwiftLint(_ testCase: Case) async throws {
        let workspace = try Self.makeWorkspace(testCase)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let swiftLintRuns = try Probe.enabledRuleIds(for: "Sub/Probe.swift", in: workspace)
        #expect(swiftLintRuns.contains(testCase.rule) == testCase.runsInSub)

        let tree = ConfigTreeDiscovery().discover(in: workspace)
        let resolved = ResolvedConfigurationEngine().resolve(
            at: workspace.appending(path: "Sub", directoryHint: .isDirectory),
            in: tree
        )
        #expect(resolved.layerChain.map(\.displayName) == ["root", "Sub"])
        // The harness reads the resolved configuration as the Config Map's verification does.
        // SwiftLint's merged configuration answers for every rule here, in place of a probe lint.
        let harness = ConfigVerificationHarness { probe, _ in swiftLintRuns.contains(probe.ruleIdentifier) }
        let report = try await harness.verify(resolved, probes: Self.probes)
        #expect(report.divergences.isEmpty, "\(report.divergences.map(\.ruleIdentifier))")

        // One rule, one row: none is named by an alias.
        let rows = ConfigMapPresenter().display(for: resolved, in: tree).ruleRows
        let aliasRows = rows.map(\.id).filter { SwiftLintDeprecations.ruleAliases[$0] != nil }
        #expect(aliasRows.isEmpty, "\(aliasRows)")
    }

    private static func makeWorkspace(_ testCase: Case) throws -> URL {
        let workspace = FileManager.default.temporaryDirectory
            .appending(path: "ResolvedConfigurationAliasAgreement-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sub = workspace.appending(path: "Sub", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let files: [URL: String] = [
            workspace.appending(path: ".swiftlint.yml"): testCase.parent,
            sub.appending(path: ".swiftlint.yml"): testCase.child,
            sub.appending(path: "Probe.swift"): "let probe = 1\n"
        ]
        for (url, content) in files {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return workspace
    }
}
