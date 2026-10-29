//
//  ResolvedConfigurationNearestConfigAgreementTests.swift
//  SwiftLintInProcessBackendTests
//
//  Which of a workspace's nested configs apply to a file, checked against the linked SwiftLint:
//  its `configuration(forDirectory:)` walks up from the file's folder and merges the root config
//  with the first nested `.swiftlint.yml` it meets, passing over the configs in the folders
//  between and those the root pulls in with `parent_config`/`child_config`, which are part of the
//  root configuration everywhere. Core's `ResolvedConfigurationEngine`, which the Config Map and
//  its verification read, must pick the same configs.
//

import Foundation
import SwiftLintRuleStudioCore
import Testing

/// Configs in up to four levels of folders, some pulled in by the root, and what SwiftLint does
/// with one rule for a file in one of them.
struct NearestConfigCase: Sendable, CustomTestStringConvertible {
    let name: String
    /// Each config's YAML, by the folder that holds it, relative to the workspace (`""` for the
    /// root).
    let configs: [String: String]
    /// The folder of the file asked about, relative to the workspace.
    let folder: String
    /// The nested configs above the file that SwiftLint passes over, root first.
    let skipped: [String]
    let rule: String
    let runs: Bool

    var testDescription: String { name }
}

/// Before, the engine merged every config from the root down to the file's folder, so a config
/// between the root and the nearest one decided rules SwiftLint never applied there.
///
/// Core is built with `.defaultIsolation(MainActor.self)`, so the suite runs on the main actor.
@MainActor
@Suite("The nested configs that apply to a file agree with the linked SwiftLint")
struct ResolvedConfigurationNearestConfigAgreementTests {
    private typealias Probe = SwiftLintConfigurationProbe

    typealias Case = NearestConfigCase

    /// A root that opts `empty_count` in, a `Sub` that disables it, and a `Sub/Deeper` that
    /// disables something else.
    nonisolated private static let threeLevels: [String: String] = [
        "": "opt_in_rules:\n  - empty_count\n",
        "Sub": "disabled_rules:\n  - empty_count\n",
        "Sub/Deeper": "disabled_rules:\n  - force_cast\n"
    ]

    /// A root that pulls `Sub`'s config in as its `child_config`, with a nested config beneath it.
    nonisolated private static let pulledInChild: [String: String] = [
        "": "opt_in_rules:\n  - empty_count\nchild_config: Sub/.swiftlint.yml\n",
        "Sub": "disabled_rules:\n  - force_cast\n",
        "Sub/Deeper": "disabled_rules:\n  - todo\n"
    ]

    nonisolated static let cases: [Case] = threeLevelCases + rootGraphCases

    nonisolated private static let threeLevelCases: [Case] = [
        Case(
            name: "A config between the root and the nearest one doesn't disable a rule the root opts in",
            configs: threeLevels,
            folder: "Sub/Deeper",
            skipped: ["Sub/.swiftlint.yml"],
            rule: "empty_count",
            runs: true
        ),
        Case(
            name: "The config between applies in its own folder",
            configs: threeLevels,
            folder: "Sub",
            skipped: [],
            rule: "empty_count",
            runs: false
        ),
        Case(
            name: "A folder with no config takes the nearest nested config above it, not the one between",
            configs: threeLevels,
            folder: "Sub/Deeper/Plain",
            skipped: ["Sub/.swiftlint.yml"],
            rule: "empty_count",
            runs: true
        ),
        Case(
            name: "A config between the root and the nearest one doesn't opt a rule in",
            configs: [
                "": "disabled_rules:\n  - todo\n",
                "Sub": "opt_in_rules:\n  - empty_count\n",
                "Sub/Deeper": "disabled_rules:\n  - force_cast\n"
            ],
            folder: "Sub/Deeper",
            skipped: ["Sub/.swiftlint.yml"],
            rule: "empty_count",
            runs: false
        ),
        Case(
            name: "A config between the root and the nearest one doesn't narrow the rules to its only_rules",
            configs: [
                "": "opt_in_rules:\n  - empty_count\n",
                "Sub": "only_rules:\n  - force_cast\n",
                "Sub/Deeper": "disabled_rules:\n  - todo\n"
            ],
            folder: "Sub/Deeper",
            skipped: ["Sub/.swiftlint.yml"],
            rule: "empty_count",
            runs: true
        ),
        Case(
            name: "With no root config, the nearest nested config applies alone",
            configs: [
                "Sub": "opt_in_rules:\n  - empty_count\n",
                "Sub/Deeper": "disabled_rules:\n  - force_cast\n"
            ],
            folder: "Sub/Deeper",
            skipped: ["Sub/.swiftlint.yml"],
            rule: "empty_count",
            runs: false
        ),
        Case(
            name: "Of three nested configs at and above a file's folder, only the nearest applies",
            configs: [
                "": "opt_in_rules:\n  - empty_count\n",
                "A": "disabled_rules:\n  - empty_count\n",
                "A/B": "opt_in_rules:\n  - force_unwrapping\n",
                "A/B/C": "disabled_rules:\n  - force_cast\n"
            ],
            folder: "A/B/C",
            skipped: ["A/.swiftlint.yml", "A/B/.swiftlint.yml"],
            rule: "force_unwrapping",
            runs: false
        )
    ]

    nonisolated private static let rootGraphCases: [Case] = [
        Case(
            name: "A config the root pulls in with child_config still applies beneath a nested config",
            configs: pulledInChild,
            folder: "Sub/Deeper",
            skipped: [],
            rule: "force_cast",
            runs: false
        ),
        Case(
            name: "A config the root pulls in with child_config applies in every folder",
            configs: pulledInChild,
            folder: "Other",
            skipped: [],
            rule: "force_cast",
            runs: false
        ),
        Case(
            name: "A config the root pulls in with parent_config merges beneath the root's own settings",
            configs: [
                "": "parent_config: Shared/.swiftlint.yml\nopt_in_rules:\n  - empty_count\n",
                "Shared": "disabled_rules:\n  - empty_count\n  - todo\n",
                "Sub": "disabled_rules:\n  - force_cast\n"
            ],
            folder: "Sub",
            skipped: [],
            rule: "empty_count",
            runs: true
        )
    ]

    /// One probe per rule SwiftLint has registered, for the harness to ask about.
    private static let probes: [RuleProbe] = Probe.registeredRules.map {
        RuleProbe(ruleIdentifier: $0.id, isOptIn: $0.isOptIn, triggeringSource: "")
    }

    @Test("The resolved configuration runs in the file's folder exactly what SwiftLint runs", arguments: cases)
    func resolvedConfigurationAgreesWithSwiftLint(_ testCase: Case) async throws {
        let workspace = try Self.makeWorkspace(testCase)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let swiftLintRuns = try Probe.enabledRuleIds(for: testCase.folder + "/Probe.swift", in: workspace)
        #expect(swiftLintRuns.contains(testCase.rule) == testCase.runs)

        let tree = ConfigTreeDiscovery().discover(in: workspace)
        let resolved = ResolvedConfigurationEngine().resolve(
            at: workspace.appending(path: testCase.folder, directoryHint: .isDirectory),
            in: tree
        )
        #expect(resolved.skippedLayers.map(\.relativePath) == testCase.skipped)

        // The harness reads the resolved configuration as the Config Map's verification does.
        // SwiftLint's merged configuration answers for every rule here, in place of a probe lint.
        let harness = ConfigVerificationHarness { probe, _ in swiftLintRuns.contains(probe.ruleIdentifier) }
        let report = try await harness.verify(resolved, probes: Self.probes)
        #expect(report.divergences.isEmpty, "\(report.divergences.map(\.ruleIdentifier))")
        // The case's own rule was among those asked about, and the engine answers it as SwiftLint does.
        let verdict = report.verifications.first { $0.ruleIdentifier == testCase.rule }
        #expect(verdict?.engineClaimsActive == testCase.runs)
    }

    private static func makeWorkspace(_ testCase: Case) throws -> URL {
        let workspace = FileManager.default.temporaryDirectory
            .appending(path: "ResolvedConfigurationNearestConfig-\(UUID().uuidString)", directoryHint: .isDirectory)
        func folder(_ relative: String) -> URL {
            relative.isEmpty ? workspace : workspace.appending(path: relative, directoryHint: .isDirectory)
        }
        var files = [folder(testCase.folder).appending(path: "Probe.swift"): "let probe = 1\n"]
        for (relative, yaml) in testCase.configs {
            files[folder(relative).appending(path: ".swiftlint.yml")] = yaml
        }
        for (url, content) in files {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return workspace
    }
}
