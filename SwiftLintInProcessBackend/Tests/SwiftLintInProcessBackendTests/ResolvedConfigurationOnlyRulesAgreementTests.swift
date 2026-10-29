//
//  ResolvedConfigurationOnlyRulesAgreementTests.swift
//  SwiftLintInProcessBackendTests
//
//  A child config beneath a parent's `only_rules`, checked against the linked SwiftLint. A
//  child in default mode edits its parent's whitelist (`RulesWrapper.mergeDefaultMode`): its
//  `opt_in_rules` and `analyzer_rules` join, and its `disabled_rules` leave. A child's own
//  `only_rules` replaces its parent's. Core's `ResolvedConfigurationEngine`, which the Config
//  Map and its verification read, must agree.
//

import Foundation
import SwiftLintRuleStudioCore
import Testing

/// A root config, a config in its `Sub` folder, and what SwiftLint runs there.
struct NestedOnlyRulesCase: Sendable, CustomTestStringConvertible {
    let name: String
    let parent: String
    let child: String
    let runsInSub: Set<String>
    let offInSub: Set<String>

    var testDescription: String { name }
}

/// Before, the engine kept the parent's `only_rules` unchanged beneath a child in default
/// mode: with `only_rules: [force_cast, force_try]` at the root and `disabled_rules: [force_try]`
/// plus `opt_in_rules: [empty_count]` in `Sub`, it claimed `force_try` ran there and
/// `empty_count` didn't. SwiftLint does the opposite.
///
/// Core is built with `.defaultIsolation(MainActor.self)`, so the suite runs on the main actor.
@MainActor
@Suite("only_rules beneath nested configs agrees with the linked SwiftLint")
struct ResolvedConfigurationOnlyRulesAgreementTests {
    private typealias Probe = SwiftLintConfigurationProbe

    typealias Case = NestedOnlyRulesCase

    nonisolated static let cases: [Case] = [
        Case(
            name: "A child disables one of its parent's only_rules and opts in another rule",
            parent: "only_rules:\n  - force_cast\n  - force_try\n",
            child: "disabled_rules:\n  - force_try\nopt_in_rules:\n  - empty_count\n",
            runsInSub: ["force_cast", "empty_count"],
            offInSub: ["force_try"]
        ),
        Case(
            name: "A child both opts in and disables a rule beneath its parent's only_rules",
            parent: "only_rules:\n  - force_cast\n",
            child: "disabled_rules:\n  - empty_count\nopt_in_rules:\n  - empty_count\n",
            runsInSub: ["force_cast"],
            offInSub: ["empty_count"]
        ),
        Case(
            name: "A parent's analyzer_rules join its only_rules",
            parent: "only_rules:\n  - force_cast\nanalyzer_rules:\n  - unused_import\n",
            child: "opt_in_rules:\n  - empty_count\n",
            runsInSub: ["force_cast", "unused_import", "empty_count"],
            offInSub: ["force_try"]
        ),
        Case(
            name: "A child's analyzer_rules join its parent's only_rules, and its disabled_rules remove one",
            parent: "only_rules:\n  - force_cast\nanalyzer_rules:\n  - unused_import\n",
            child: "analyzer_rules:\n  - unused_declaration\n  - capture_variable\n"
                + "disabled_rules:\n  - unused_import\n  - capture_variable\n",
            runsInSub: ["force_cast", "unused_declaration"],
            offInSub: ["unused_import", "capture_variable"]
        ),
        Case(
            name: "A child's only_rules replaces its parent's, analyzer_rules included",
            parent: "only_rules:\n  - force_cast\n  - force_try\nanalyzer_rules:\n  - unused_import\n",
            child: "only_rules:\n  - todo\nanalyzer_rules:\n  - unused_declaration\n",
            runsInSub: ["todo", "unused_declaration"],
            offInSub: ["force_cast", "force_try", "unused_import"]
        ),
        Case(
            name: "A child's only_rules runs a rule its parent disables, and drops its parent's opt-ins",
            parent: "disabled_rules:\n  - todo\nopt_in_rules:\n  - empty_count\n",
            child: "only_rules:\n  - todo\n",
            runsInSub: ["todo"],
            offInSub: ["empty_count", "force_cast"]
        ),
        Case(
            name: "A child edits its parent's only_rules by the rules' aliases",
            parent: "only_rules:\n  - identifier_name\n  - force_cast\n",
            child: "disabled_rules:\n  - variable_name\nopt_in_rules:\n  - if_let_shadowing\n",
            runsInSub: ["force_cast", "shorthand_optional_binding"],
            offInSub: ["identifier_name"]
        ),
        Case(
            name: "An empty only_rules is no whitelist",
            parent: "only_rules: []\ndisabled_rules:\n  - todo\n",
            child: "opt_in_rules:\n  - empty_count\n",
            runsInSub: ["force_cast", "empty_count"],
            offInSub: ["todo"]
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
        #expect(testCase.runsInSub.isSubset(of: swiftLintRuns), "\(testCase.runsInSub.subtracting(swiftLintRuns))")
        #expect(testCase.offInSub.isDisjoint(with: swiftLintRuns), "\(testCase.offInSub.intersection(swiftLintRuns))")

        let tree = ConfigTreeDiscovery().discover(in: workspace)
        let resolved = ResolvedConfigurationEngine().resolve(
            at: workspace.appending(path: "Sub", directoryHint: .isDirectory),
            in: tree
        )
        // The harness reads the resolved configuration as the Config Map's verification does.
        // SwiftLint's merged configuration answers for every rule here, in place of a probe lint.
        let harness = ConfigVerificationHarness { probe, _ in swiftLintRuns.contains(probe.ruleIdentifier) }
        let report = try await harness.verify(resolved, probes: Self.probes)
        #expect(report.divergences.isEmpty, "\(report.divergences.map(\.ruleIdentifier))")

        // The Config Map reads the same: no rule SwiftLint runs shows as off, and no row for a
        // rule it skips says otherwise.
        let rows = ConfigMapPresenter().display(for: resolved, in: tree).ruleRows
        let misread = rows.filter { $0.state.hasPrefix("off") == swiftLintRuns.contains($0.id) }
        #expect(misread.isEmpty, "\(misread.map { "\($0.id): \($0.state)" })")
    }

    private static func makeWorkspace(_ testCase: Case) throws -> URL {
        let workspace = FileManager.default.temporaryDirectory
            .appending(path: "OnlyRulesAgreement-\(UUID().uuidString)", directoryHint: .isDirectory)
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
