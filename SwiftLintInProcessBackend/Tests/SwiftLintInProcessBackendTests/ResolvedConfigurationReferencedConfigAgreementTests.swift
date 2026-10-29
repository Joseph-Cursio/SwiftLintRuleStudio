//
//  ResolvedConfigurationReferencedConfigAgreementTests.swift
//  SwiftLintInProcessBackendTests
//
//  The configs the root config pulls in from beyond the workspace's own `.swiftlint.yml` files,
//  checked against the linked SwiftLint: a package's `parent_config: ../../.swiftlint.yml`, a
//  file under another name, a remote config. SwiftLint builds the root configuration from all
//  of them, from the furthest parent down to the last child, and applies it in every folder.
//  Core's `ResolvedConfigurationEngine`, which the Config Map and its verification read, must
//  merge the same configs in the same order.
//

import Foundation
import SwiftLintRuleStudioCore
import Testing

/// Configs in and around a package opened on its own, and what SwiftLint does with one rule
/// for a file in one of its folders.
struct ReferencedConfigCase: Sendable, CustomTestStringConvertible {
    let name: String
    /// Each config file's YAML, by its path from the workspace, which is opened at
    /// `Packages/Foo` in a repository: `../../.swiftlint.yml` is the repository's config.
    let files: [String: String]
    /// The copy SwiftLint keeps of each remote config, by URL. Each URL names a port nothing
    /// listens on, so SwiftLint's fetch fails at once and it lints with its copy, as it does
    /// offline.
    let remote: [String: String]
    /// The folder of the file asked about, relative to the workspace.
    let folder: String
    /// The resolved layer chain, as each layer's path from the workspace or URL.
    let chain: [String]
    let rule: String
    let runs: Bool

    init(
        name: String,
        files: [String: String],
        chain: [String],
        runs: Bool,
        remote: [String: String] = [:],
        folder: String = "Sources",
        rule: String = "empty_count"
    ) {
        self.name = name
        self.files = files
        self.remote = remote
        self.folder = folder
        self.chain = chain
        self.rule = rule
        self.runs = runs
    }

    var testDescription: String { name }
}

/// Before, the engine dropped every config the root pulled in from outside the workspace, so a
/// package that inherits a repository's config showed none of its rules.
///
/// Core is built with `.defaultIsolation(MainActor.self)`, so the suite runs on the main actor.
@MainActor
@Suite("The configs the root pulls in from beyond the workspace agree with the linked SwiftLint")
struct ResolvedConfigurationReferencedConfigAgreementTests {
    private typealias Probe = SwiftLintConfigurationProbe

    typealias Case = ReferencedConfigCase

    nonisolated private static let optIn = "opt_in_rules:\n  - empty_count\n"
    nonisolated private static let disable = "disabled_rules:\n  - empty_count\n"
    nonisolated private static let remoteBase = "http://127.0.0.1:9/base.yml"
    nonisolated private static let remoteStrict = "http://127.0.0.1:9/strict.yml"

    nonisolated static let cases: [Case] = fileCases + remoteCases

    nonisolated private static let fileCases: [Case] = [
        Case(
            name: "A package's parent_config outside the workspace opts a rule in everywhere",
            files: [".swiftlint.yml": "parent_config: ../../.swiftlint.yml\n", "../../.swiftlint.yml": optIn],
            chain: ["../../.swiftlint.yml", ".swiftlint.yml"],
            runs: true
        ),
        Case(
            name: "The package's own config overrides the parent_config outside the workspace",
            files: [
                ".swiftlint.yml": "parent_config: ../../.swiftlint.yml\n" + disable,
                "../../.swiftlint.yml": optIn
            ],
            chain: ["../../.swiftlint.yml", ".swiftlint.yml"],
            runs: false
        ),
        Case(
            name: "A nested config in the package merges onto the parent_config outside the workspace",
            files: [
                ".swiftlint.yml": "parent_config: ../../.swiftlint.yml\n",
                "../../.swiftlint.yml": optIn,
                "Sub/.swiftlint.yml": disable
            ],
            chain: ["../../.swiftlint.yml", ".swiftlint.yml", "Sub/.swiftlint.yml"],
            runs: false,
            folder: "Sub"
        ),
        Case(
            name: "The outside parent_config's own parent_config merges beneath it",
            files: [
                ".swiftlint.yml": "parent_config: ../../.swiftlint.yml\n",
                "../../.swiftlint.yml": "parent_config: Shared/base.yml\ndisabled_rules:\n  - todo\n",
                "../../Shared/base.yml": optIn
            ],
            chain: ["../../Shared/base.yml", "../../.swiftlint.yml", ".swiftlint.yml"],
            runs: true
        ),
        Case(
            name: "A child_config outside the workspace overrides the root config",
            files: [".swiftlint.yml": "child_config: ../Shared/strict.yml\n" + optIn, "../Shared/strict.yml": disable],
            chain: [".swiftlint.yml", "../Shared/strict.yml"],
            runs: false
        ),
        Case(
            name: "A child_config in the workspace under another name applies everywhere",
            files: [".swiftlint.yml": "child_config: Config/strict.yml\n", "Config/strict.yml": optIn],
            chain: [".swiftlint.yml", "Config/strict.yml"],
            runs: true
        ),
        Case(
            name: "A parent_config that doesn't exist is ignored",
            files: [".swiftlint.yml": "parent_config: ../../missing.yml\n" + optIn],
            chain: [".swiftlint.yml"],
            runs: true
        )
    ]

    nonisolated private static let remoteCases: [Case] = [
        Case(
            name: "A remote parent_config opts a rule in as SwiftLint's copy of it says",
            files: [".swiftlint.yml": "parent_config: \(remoteBase)\n"],
            chain: [remoteBase, ".swiftlint.yml"],
            runs: true,
            remote: [remoteBase: optIn]
        ),
        Case(
            name: "The root config overrides its remote parent_config",
            files: [".swiftlint.yml": "parent_config: \(remoteBase)\n" + disable],
            chain: [remoteBase, ".swiftlint.yml"],
            runs: false,
            remote: [remoteBase: optIn]
        ),
        Case(
            name: "A remote child_config overrides the root config",
            files: [".swiftlint.yml": "child_config: \(remoteStrict)\n" + optIn],
            chain: [".swiftlint.yml", remoteStrict],
            runs: false,
            remote: [remoteStrict: disable]
        )
    ]

    /// What SwiftLint excludes, includes and reports with, for a package in a repository.
    struct RootSettingsCase: Sendable, CustomTestStringConvertible {
        let name: String
        /// As ``ReferencedConfigCase/files``.
        let files: [String: String]
        /// As ``ReferencedConfigCase/remote``.
        var remote: [String: String] = [:]
        /// The root configuration's `excluded`, each entry a path from the workspace.
        let excluded: [String]
        var included: [String] = []
        /// SwiftLint's own reporter name; `xcode` is its default.
        var reporter = "xcode"

        var testDescription: String { name }
    }

    nonisolated static let rootSettingsCases: [RootSettingsCase] = [
        RootSettingsCase(
            name: "A package's parent_config outside the workspace excludes a folder beside the package",
            files: [
                ".swiftlint.yml": "parent_config: ../../.swiftlint.yml\nexcluded:\n  - Generated\n",
                "../../.swiftlint.yml": "excluded:\n  - Pods\n"
            ],
            excluded: ["../../Pods", "Generated"]
        ),
        RootSettingsCase(
            name: "The package's included takes back its parent's exclusion of the same folder",
            files: [
                ".swiftlint.yml": "parent_config: ../../.swiftlint.yml\nincluded:\n  - Sources\n",
                "../../.swiftlint.yml": "excluded:\n  - Packages/Foo/Sources\n  - Pods\n"
            ],
            excluded: ["../../Pods"],
            included: ["Sources"]
        ),
        RootSettingsCase(
            name: "A child_config's exclusion drops the root's inclusion of the same folder",
            files: [
                ".swiftlint.yml": "child_config: ../Shared/strict.yml\nincluded:\n  - Sources\n  - Tests\n",
                "../Shared/strict.yml": "excluded:\n  - ../Foo/Tests\n"
            ],
            excluded: ["Tests"],
            included: ["Sources"]
        ),
        RootSettingsCase(
            name: "A remote config's excluded is read from the folder of the config that pulls it in",
            files: [".swiftlint.yml": "parent_config: \(remoteBase)\n"],
            remote: [remoteBase: "excluded:\n  - Generated\n"],
            excluded: ["Generated"]
        ),
        RootSettingsCase(
            name: "A nested config's excluded is ignored",
            files: [".swiftlint.yml": "excluded:\n  - Generated\n", "Sub/.swiftlint.yml": "excluded:\n  - Legacy\n"],
            excluded: ["Generated"]
        ),
        RootSettingsCase(
            name: "The root config's reporter gives way to its parent_config's default",
            files: [
                ".swiftlint.yml": "parent_config: ../../.swiftlint.yml\nreporter: json\n",
                "../../.swiftlint.yml": "excluded:\n  - Pods\n"
            ],
            excluded: ["../../Pods"]
        ),
        RootSettingsCase(
            name: "The reporter is the furthest parent_config's",
            files: [
                ".swiftlint.yml": "parent_config: ../../.swiftlint.yml\nreporter: json\n",
                "../../.swiftlint.yml": "reporter: emoji\n"
            ],
            excluded: [],
            reporter: "emoji"
        )
    ]

    @Test("The resolved excluded, included and reporter are SwiftLint's", arguments: rootSettingsCases)
    func rootSettingsAgreeWithSwiftLint(_ testCase: RootSettingsCase) throws {
        let (repository, workspace) = try Self.makeWorkspace(
            Case(name: testCase.name, files: testCase.files, chain: [], runs: false, remote: testCase.remote)
        )
        defer { try? FileManager.default.removeItem(at: repository) }
        func absolute(_ paths: [String]) -> [String] {
            paths.map { workspace.appending(path: $0).standardizedFileURL.path }
        }

        let swiftLint = try Probe.rootSettings(in: workspace)
        #expect(swiftLint.excluded == absolute(testCase.excluded))
        #expect(swiftLint.included == absolute(testCase.included))
        #expect(swiftLint.reporter == testCase.reporter)

        let resolved = ResolvedConfigurationEngine().resolve(
            at: workspace.appending(path: "Sub", directoryHint: .isDirectory),
            in: ConfigTreeDiscovery().discover(in: workspace)
        )
        #expect(absolute(resolved.excluded.map(\.value)) == swiftLint.excluded)
        #expect(absolute(resolved.included.map(\.value)) == swiftLint.included)
        #expect(resolved.reporter?.value ?? "xcode" == swiftLint.reporter)
    }

    /// One probe per rule SwiftLint has registered, for the harness to ask about.
    private static let probes: [RuleProbe] = Probe.registeredRules.map {
        RuleProbe(ruleIdentifier: $0.id, isOptIn: $0.isOptIn, triggeringSource: "")
    }

    @Test("The resolved configuration runs in the file's folder exactly what SwiftLint runs", arguments: cases)
    func resolvedConfigurationAgreesWithSwiftLint(_ testCase: Case) async throws {
        let (repository, workspace) = try Self.makeWorkspace(testCase)
        defer { try? FileManager.default.removeItem(at: repository) }

        let swiftLintRuns = try Probe.enabledRuleIds(for: testCase.folder + "/Probe.swift", in: workspace)
        #expect(swiftLintRuns.contains(testCase.rule) == testCase.runs)

        let tree = ConfigTreeDiscovery().discover(in: workspace)
        let resolved = ResolvedConfigurationEngine().resolve(
            at: workspace.appending(path: testCase.folder, directoryHint: .isDirectory),
            in: tree
        )
        #expect(resolved.layerChain.map(\.relativePath) == testCase.chain)

        // The harness reads the resolved configuration as the Config Map's verification does.
        // SwiftLint's merged configuration answers for every rule here, in place of a probe lint.
        let harness = ConfigVerificationHarness { probe, _ in swiftLintRuns.contains(probe.ruleIdentifier) }
        let report = try await harness.verify(resolved, probes: Self.probes)
        #expect(report.divergences.isEmpty, "\(report.divergences.map(\.ruleIdentifier))")
        let verdict = report.verifications.first { $0.ruleIdentifier == testCase.rule }
        #expect(verdict?.engineClaimsActive == testCase.runs)
    }

    /// A repository holding the case's files, with the workspace at `Packages/Foo` holding a
    /// Swift file in the case's folder, and SwiftLint's copies of the remote configs.
    static func makeWorkspace(_ testCase: Case) throws -> (repository: URL, workspace: URL) {
        let repository = FileManager.default.temporaryDirectory
            .appending(path: "ResolvedConfigurationReferencedConfig-\(UUID().uuidString)", directoryHint: .isDirectory)
        let workspace = repository.appending(path: "Packages/Foo", directoryHint: .isDirectory)
        var files = [
            workspace.appending(path: testCase.folder, directoryHint: .isDirectory).appending(path: "Probe.swift"):
                "let probe = 1\n"
        ]
        for (path, yaml) in testCase.files {
            files[workspace.appending(path: path).standardizedFileURL] = yaml
        }
        for (reference, yaml) in testCase.remote {
            files[ConfigTreeDiscovery.remoteConfigCacheURL(for: reference, in: workspace)] = yaml
        }
        for (url, content) in files {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return (repository, workspace)
    }
}
