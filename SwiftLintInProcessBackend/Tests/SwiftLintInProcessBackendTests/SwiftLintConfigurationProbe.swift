//
//  SwiftLintConfigurationProbe.swift
//  SwiftLintInProcessBackendTests
//
//  What the linked SwiftLint itself makes of a `.swiftlint.yml`, in plain Swift types.
//
//  Kept apart from the tests that compare it with Core: SwiftLintFramework and Core both
//  declare `Rule`, `RuleRegistry` and `Severity`, so no one file can import both and use
//  either unqualified.
//

import Foundation
import SwiftLintFramework
@testable import SwiftLintInProcessBackend

/// SwiftLint's own reading of a configuration, through ``InProcessConfiguration`` — the
/// path the sandboxed edition lints with, which hands the file to SwiftLint's loader,
/// `Configuration(configurationFiles:)` — so nothing here re-implements SwiftLint's rules.
enum SwiftLintConfigurationProbe {
    /// A rule SwiftLint has registered, classified by the protocols it conforms to.
    struct RegisteredRule: Sendable {
        let id: String
        /// Conforms to `OptInRule`. So does every analyzer rule: `AnalyzerRule` refines it.
        let isOptIn: Bool
        /// Conforms to `AnalyzerRule`.
        let isAnalyzer: Bool
    }

    /// A configuration SwiftLint accepted.
    struct Accepted: Sendable {
        /// The identifiers of every rule in `Configuration.rules`. That includes analyzer
        /// rules: `Linter.init` drops them for `swiftlint lint` and keeps only them for
        /// `swiftlint analyze`, so this is the set both commands draw from.
        let enabledRuleIds: Set<String>
        /// `included` as SwiftLint resolved it, relative to the config's folder.
        let included: [String]
        /// `excluded` as SwiftLint resolved it, relative to the config's folder.
        let excluded: [String]
        let strict: Bool
        /// Each enabled rule's settings as SwiftLint parsed them, in its one-line form
        /// (`severity: warning; mandatory_comma: true`).
        let settings: [String: String]
    }

    enum Outcome: Sendable {
        case accepted(Accepted)
        /// SwiftLint refused the file. `reason` carries its message.
        case rejected(reason: String)

        var accepted: Accepted? {
            if case let .accepted(accepted) = self { accepted } else { nil }
        }

        var rejectionReason: String? {
            if case let .rejected(reason) = self { reason } else { nil }
        }
    }

    /// Every rule the in-process SwiftLint has registered.
    static var registeredRules: [RegisteredRule] {
        SwiftLintInProcessActor.prepare()
        return RuleRegistry.shared.list.list
            .map { id, ruleType in
                RegisteredRule(
                    id: id,
                    isOptIn: ruleType is any OptInRule.Type,
                    isAnalyzer: ruleType is any AnalyzerRule.Type
                )
            }
            .sorted { $0.id < $1.id }
    }

    /// Writes `yaml` as the `.swiftlint.yml` of a fresh workspace and loads it the way an
    /// in-process lint of that workspace does.
    static func load(_ yaml: String) throws -> Outcome {
        SwiftLintInProcessActor.prepare()
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintConfigurationProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try yaml.write(
            to: workspace.appendingPathComponent(Configuration.defaultFileName),
            atomically: true,
            encoding: .utf8
        )

        let configuration: Configuration
        do {
            // In the workspace, as a lint runs: SwiftLint's loader looks for the file there.
            configuration = try CurrentWorkingDirectory.$url.withValue(workspace) {
                try InProcessConfiguration.root(configPath: nil, workspacePath: workspace).configuration
            }
        } catch let InProcessConfigurationError.unreadable(_, reason) {
            return .rejected(reason: reason)
        }

        let base = workspace.standardizedFileURL.path + "/"
        func relative(_ url: URL) -> String {
            let path = url.standardizedFileURL.path
            return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
        }
        return .accepted(Accepted(
            enabledRuleIds: Set(configuration.rules.map { type(of: $0).identifier }),
            included: configuration.includedPaths.map(relative),
            excluded: configuration.excludedPaths.map(relative),
            strict: configuration.strict,
            settings: Dictionary(uniqueKeysWithValues: configuration.rules.map { rule in
                (type(of: rule).identifier, rule.createConfigurationDescription().oneLiner())
            })
        ))
    }

    /// The identifiers of the rules SwiftLint runs on `file`, a Swift file in `workspace` whose
    /// `.swiftlint.yml` files are already written: the root configuration merged with the nested
    /// config SwiftLint's search finds for that file, each built as an in-process lint builds it.
    static func enabledRuleIds(for file: String, in workspace: URL) throws -> Set<String> {
        SwiftLintInProcessActor.prepare()
        return try CurrentWorkingDirectory.$url.withValue(workspace) {
            let (root, fileGraph) = try SwiftLintInProcessActor.withConfigurationCaches {
                try InProcessConfiguration.root(configPath: nil, workspacePath: workspace)
            }
            // Taken from SwiftLint's own file walk, so the nested-config search starts from the
            // file's folder spelled as a lint spells it.
            let files = root.lintableFiles(inPath: workspace, forceExclude: false, excludeByPrefix: false)
            guard let lintable = files.first(where: { $0.path?.path.hasSuffix("/" + file) == true }) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: file])
            }
            try InProcessConfiguration.checkNestedConfigs(for: [lintable], root: root, fileGraph: fileGraph)
            let configuration = SwiftLintInProcessActor.withConfigurationCaches { root.configuration(for: lintable) }
            return Set(configuration.rules.map { type(of: $0).identifier })
        }
    }
}
