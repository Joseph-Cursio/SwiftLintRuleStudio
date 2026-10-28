import Foundation
import SwiftLintFramework
@testable import SwiftLintInProcessBackend
import Testing

/// In-process, SwiftLint ends the app on a nested config it can't use, so the backend checks
/// every config SwiftLint's nested-config search will load before the lint. These tests put
/// one contested `.swiftlint.yml` where that search does or doesn't reach, and pin both
/// SwiftLint's search and the check against it.
@Suite(.serialized)
struct InProcessNestedConfigSearchTests {
    enum Contested: String, CaseIterable, CustomTestStringConvertible {
        /// Above the root's `child_config`, which the search passes over as part of the root.
        case aboveChildConfig
        /// Beside an `included` folder that is a link: the search goes through the link.
        case besideLink
        /// Beside that link's target, which the search never visits.
        case besideLinkTarget
        /// Above the workspace, where the search stops.
        case aboveWorkspace
        /// Above a workspace opened under `/private`, with no config of its own. With no
        /// `excluded`, SwiftLint's file walk drops the prefix, so the search never meets the
        /// workspace and goes on above it.
        case abovePrivateWorkspace
        /// The same, with a config naming a `child_config`. The search meets that config,
        /// without the prefix, and passes over it as part of the root.
        case abovePrivateWorkspaceWithChildConfig
        /// The same, with a config naming none. Built by SwiftLint's loader, as `swiftlint lint`
        /// builds it, the root holds that config in its file graph, so the search passes over it
        /// too (#102).
        case abovePrivateWorkspaceWithConfig
        /// The same, with a config that has `excluded`. The walk then keeps the prefix, so the
        /// search meets the workspace and stops.
        case abovePrivateWorkspaceWithExcluded

        var isLoaded: Bool {
            switch self {
            case .aboveChildConfig, .besideLink, .abovePrivateWorkspace, .abovePrivateWorkspaceWithChildConfig,
                 .abovePrivateWorkspaceWithConfig: true
            case .besideLinkTarget, .aboveWorkspace, .abovePrivateWorkspaceWithExcluded: false
            }
        }

        var testDescription: String { rawValue }

        /// Where the contested config goes, from the folder holding the workspace `ws`.
        var path: String {
            switch self {
            case .aboveChildConfig: "ws/Mod/.swiftlint.yml"
            case .besideLink: "ws/Libs/.swiftlint.yml"
            case .besideLinkTarget: "ws/Shared/.swiftlint.yml"
            case .aboveWorkspace, .abovePrivateWorkspace, .abovePrivateWorkspaceWithChildConfig,
                 .abovePrivateWorkspaceWithConfig, .abovePrivateWorkspaceWithExcluded: ".swiftlint.yml"
            }
        }

        var isUnderPrivate: Bool {
            switch self {
            case .abovePrivateWorkspace, .abovePrivateWorkspaceWithChildConfig, .abovePrivateWorkspaceWithConfig,
                 .abovePrivateWorkspaceWithExcluded: true
            case .aboveChildConfig, .besideLink, .besideLinkTarget, .aboveWorkspace: false
            }
        }
    }

    private static let optInRule = "empty_count"
    private static let source = "let values: [Int] = []\nlet isEmpty = values.count == 0\n"
    private static let plainConfig = "disabled_rules:\n  - trailing_newline\n"

    private struct Layout {
        let base: URL
        let workspace: URL

        func remove() {
            try? FileManager.default.removeItem(at: base)
        }
    }

    /// A workspace at `<base>/ws`, with `config` as the contested `.swiftlint.yml`.
    private func makeLayout(_ contested: Contested, config: String) throws -> Layout {
        let base = try makeBase(underPrivate: contested.isUnderPrivate)
        var files: [String: String] = switch contested {
        case .aboveChildConfig: [
            "ws/.swiftlint.yml": "child_config: Mod/Core/.swiftlint.yml\n",
            "ws/Mod/Core/.swiftlint.yml": Self.plainConfig,
            "ws/Mod/Core/A.swift": Self.source
        ]
        case .besideLink, .besideLinkTarget: [
            "ws/.swiftlint.yml": "included:\n  - Libs/Vendor\n",
            "ws/Shared/Vendor/X.swift": Self.source
        ]
        case .aboveWorkspace, .abovePrivateWorkspace: ["ws/Sub/A.swift": Self.source]
        case .abovePrivateWorkspaceWithChildConfig: [
            "ws/.swiftlint.yml": "child_config: .swiftlint.local.yml\n",
            "ws/.swiftlint.local.yml": Self.plainConfig,
            "ws/Sub/A.swift": Self.source
        ]
        case .abovePrivateWorkspaceWithConfig: ["ws/.swiftlint.yml": Self.plainConfig, "ws/Sub/A.swift": Self.source]
        case .abovePrivateWorkspaceWithExcluded: [
            "ws/.swiftlint.yml": Self.plainConfig + "excluded:\n  - Build\n",
            "ws/Sub/A.swift": Self.source
        ]
        }
        files[contested.path] = config

        for (path, content) in files {
            let url = base.appending(path: path, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        if contested == .besideLink || contested == .besideLinkTarget {
            let libs = base.appending(path: "ws/Libs", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: libs, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                atPath: libs.appending(path: "Vendor").path,
                withDestinationPath: "../Shared/Vendor"
            )
        }
        return Layout(base: base, workspace: base.appending(path: "ws", directoryHint: .isDirectory))
    }

    /// A fresh folder in the temporary directory. Under `/private`, it is spelled by its real
    /// path, as an open panel gives a folder in `/tmp` or `/var`.
    private func makeBase(underPrivate: Bool) throws -> URL {
        var temporary = FileManager.default.temporaryDirectory
        if underPrivate {
            let real = try #require(realpath(temporary.path, nil))
            defer { free(real) }
            temporary = URL(fileURLWithPath: String(cString: real), isDirectory: true)
            try #require(temporary.path.hasPrefix("/private/"), "the temporary directory isn't under /private")
        }
        return temporary.appending(
            path: "InProcessNestedConfigSearchTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }

    @Test("SwiftLint applies the contested config just where its search reaches it", arguments: Contested.allCases)
    func swiftLintLoadsReachedConfig(_ contested: Contested) async throws {
        let layout = try makeLayout(contested, config: "opt_in_rules:\n  - \(Self.optInRule)\n")
        defer { layout.remove() }

        let data = try await SwiftLintInProcessActor().executeLintCommand(
            configPath: nil,
            workspacePath: layout.workspace
        )
        // A walk that found nothing would have failed the lint.
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(json.contains { $0["rule_id"] as? String == Self.optInRule } == contested.isLoaded)
    }

    @Test(
        "The check reads the contested config just where SwiftLint's search reaches it",
        arguments: Contested.allCases
    )
    func checkReadsReachedConfig(_ contested: Contested) throws {
        let layout = try makeLayout(contested, config: "swiftlint_version: 0.0.1\n")
        defer { layout.remove() }

        // The check alone: were it to miss this config, a lint would end the test process.
        if contested.isLoaded {
            #expect(throws: InProcessConfigurationError.self) {
                try InProcessConfiguration.checkNestedConfigs(in: layout.workspace)
            }
        } else {
            #expect(throws: Never.self) {
                try InProcessConfiguration.checkNestedConfigs(in: layout.workspace)
            }
        }
    }

    @Test(
        "A config SwiftLint's search reaches and would end the app for is an error, not a crash",
        arguments: Contested.allCases.filter(\.isLoaded), [
            "only_rules:\n  - force_cast\nopt_in_rules:\n  - empty_count\n",
            "swiftlint_version: 0.0.1\n"
        ]
    )
    func badReachedConfigFailsTheLint(_ contested: Contested, config: String) async throws {
        let layout = try makeLayout(contested, config: config)
        defer { layout.remove() }

        // The check first, on its own: were it to miss this config, the lint below would end
        // the test process rather than fail the test.
        guard (try? InProcessConfiguration.checkNestedConfigs(in: layout.workspace)) == nil else {
            Issue.record("the nested-config check let a config SwiftLint rejects through; not linting")
            return
        }

        await #expect(throws: InProcessConfigurationError.self) {
            _ = try await SwiftLintInProcessActor().executeLintCommand(configPath: nil, workspacePath: layout.workspace)
        }
    }
}

extension InProcessConfiguration {
    /// The nested-config check a lint of `workspace` makes, on the files its walk finds, alone.
    static func checkNestedConfigs(in workspace: URL) throws {
        SwiftLintInProcessActor.prepare()
        try CurrentWorkingDirectory.$url.withValue(workspace) {
            let (configuration, fileGraph) = try root(configPath: nil, workspacePath: workspace)
            let files = configuration.lintableFiles(inPath: workspace, forceExclude: false, excludeByPrefix: false)
            try checkNestedConfigs(for: files, root: configuration, fileGraph: fileGraph)
        }
    }
}
