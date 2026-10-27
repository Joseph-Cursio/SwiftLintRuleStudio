import Foundation
import SwiftLintFramework
@testable import SwiftLintInProcessBackend
import Testing

/// How the in-process backend finds and re-reads `.swiftlint.yml`.
///
/// The subprocess backend runs a fresh `swiftlint` process each time, with the workspace
/// as its working directory. The in-process backend has neither: the app's working
/// directory isn't the workspace, and SwiftLint's configuration cache outlives a call.
/// These tests pin the behaviour the app relies on — rule simulation in particular
/// rewrites the same config file once per rule and lints again.
@Suite(.serialized)
struct InProcessLintConfigurationTests {
    /// `empty_count` is opt-in, so it only reports when a config enables it.
    private static let optInRule = "empty_count"
    private static let source = """
        let values: [Int] = []
        let isEmpty = values.count == 0

        """

    /// A workspace in a fresh temporary folder with one Swift file and, optionally, a config.
    private func makeWorkspace(config: String?) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessLintConfigurationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.source.write(to: folder.appendingPathComponent("Sample.swift"), atomically: true, encoding: .utf8)
        if let config {
            try writeConfig(config, in: folder)
        }
        return folder
    }

    private func writeConfig(_ config: String, in folder: URL) throws {
        try config.write(to: folder.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
    }

    /// The rules a lint reports. With a config path, that config alone applies, as with
    /// `--config`; the workspace analysis never lints that way (see `analyzedRuleIDs`).
    private func ruleIDs(configPath: URL?, workspace: URL) async throws -> Set<String> {
        // Off the caller's executor, as the backend runs it.
        try await ruleIDs(in: Task.detached {
            try SwiftLintInProcessActor.lint(configPath: configPath, workspacePath: workspace)
        }.value)
    }

    /// The rules the workspace analysis reports, which names the workspace's own config.
    private func analyzedRuleIDs(in workspace: URL) async throws -> Set<String> {
        try await ruleIDs(in: SwiftLintInProcessActor().executeLintCommand(
            configPath: workspace.appendingPathComponent(".swiftlint.yml"),
            workspacePath: workspace
        ))
    }

    private func ruleIDs(in data: Data) throws -> Set<String> {
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        return Set(json.compactMap { $0["rule_id"] as? String })
    }

    @Test("Without a config path, the workspace's own .swiftlint.yml applies")
    func discoversWorkspaceConfig() async throws {
        let workspace = try makeWorkspace(config: "opt_in_rules:\n  - \(Self.optInRule)\n")
        #expect(try await ruleIDs(configPath: nil, workspace: workspace).contains(Self.optInRule))
    }

    @Test("Without a config path or a .swiftlint.yml, opt-in rules stay off")
    func noConfigMeansDefaults() async throws {
        let workspace = try makeWorkspace(config: nil)
        #expect(try await !ruleIDs(configPath: nil, workspace: workspace).contains(Self.optInRule))
    }

    @Test("Rewriting the discovered config takes effect on the next lint")
    func rereadsDiscoveredConfig() async throws {
        let workspace = try makeWorkspace(config: "opt_in_rules:\n  - \(Self.optInRule)\n")
        #expect(try await ruleIDs(configPath: nil, workspace: workspace).contains(Self.optInRule))

        try writeConfig("disabled_rules:\n  - trailing_newline\n", in: workspace)
        #expect(try await !ruleIDs(configPath: nil, workspace: workspace).contains(Self.optInRule))

        try writeConfig("opt_in_rules:\n  - \(Self.optInRule)\n", in: workspace)
        #expect(try await ruleIDs(configPath: nil, workspace: workspace).contains(Self.optInRule))
    }

    @Test("Rewriting an explicit config takes effect on the next lint")
    func rereadsExplicitConfig() async throws {
        let workspace = try makeWorkspace(config: "opt_in_rules:\n  - \(Self.optInRule)\n")
        let configPath = workspace.appendingPathComponent(".swiftlint.yml")
        #expect(try await ruleIDs(configPath: configPath, workspace: workspace).contains(Self.optInRule))

        try writeConfig("disabled_rules:\n  - trailing_newline\n", in: workspace)
        #expect(try await !ruleIDs(configPath: configPath, workspace: workspace).contains(Self.optInRule))
    }

    @Test("A nested config applies to the files beneath it")
    func appliesNestedConfig() async throws {
        let workspace = try makeWorkspace(config: "disabled_rules:\n  - trailing_newline\n")
        let nested = workspace.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Self.source.write(to: nested.appendingPathComponent("Inner.swift"), atomically: true, encoding: .utf8)
        try writeConfig("opt_in_rules:\n  - \(Self.optInRule)\n", in: nested)

        let data = try await SwiftLintInProcessActor().executeLintCommand(configPath: nil, workspacePath: workspace)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let files = Set(json.filter { $0["rule_id"] as? String == Self.optInRule }
            .compactMap { ($0["file"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } })
        #expect(files == ["Inner.swift"], "only the nested folder enables the rule")
    }

    // MARK: - SwiftLint's configuration caches

    /// The analysis of a workspace with no `.swiftlint.yml` lints its folder without a config
    /// path, at the same path every time, and SwiftLint caches each nested config by path.
    @Test("Rewriting a nested config takes effect on the next lint")
    func rereadsNestedConfig() async throws {
        let workspace = try makeWorkspace(config: nil)
        let nested = workspace.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Self.source.write(to: nested.appendingPathComponent("Inner.swift"), atomically: true, encoding: .utf8)
        try writeConfig("opt_in_rules:\n  - \(Self.optInRule)\n", in: nested)
        #expect(try await ruleIDs(configPath: nil, workspace: workspace).contains(Self.optInRule))

        try writeConfig("disabled_rules:\n  - trailing_newline\n", in: nested)
        #expect(try await !ruleIDs(configPath: nil, workspace: workspace).contains(Self.optInRule))
    }

    /// SwiftLint also remembers, by path, each folder it found no nested config for.
    @Test("A nested config added after a lint applies on the next one")
    func seesAddedNestedConfig() async throws {
        let workspace = try makeWorkspace(config: nil)
        let nested = workspace.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Self.source.write(to: nested.appendingPathComponent("Inner.swift"), atomically: true, encoding: .utf8)
        #expect(try await !ruleIDs(configPath: nil, workspace: workspace).contains(Self.optInRule))

        try writeConfig("opt_in_rules:\n  - \(Self.optInRule)\n", in: nested)
        #expect(try await ruleIDs(configPath: nil, workspace: workspace).contains(Self.optInRule))
    }

    /// A config that names a `parent_config` is loaded by SwiftLint's file loader, which caches
    /// the result by path.
    @Test("Rewriting a parent config takes effect on the next lint", arguments: [true, false])
    func rereadsParentConfig(explicitConfig: Bool) async throws {
        let workspace = try makeWorkspace(config: "parent_config: base.yml\n")
        let parent = workspace.appendingPathComponent("base.yml")
        try "opt_in_rules:\n  - \(Self.optInRule)\n".write(to: parent, atomically: true, encoding: .utf8)
        let configPath = explicitConfig ? workspace.appendingPathComponent(".swiftlint.yml") : nil
        #expect(try await ruleIDs(configPath: configPath, workspace: workspace).contains(Self.optInRule))

        try "disabled_rules:\n  - trailing_newline\n".write(to: parent, atomically: true, encoding: .utf8)
        #expect(try await !ruleIDs(configPath: configPath, workspace: workspace).contains(Self.optInRule))
    }

    /// A lint of the same folder can still be running — an analysis superseded by a newer one
    /// can't be stopped — and SwiftLint keeps what it read in caches shared by every lint. Here
    /// the configs it would have read are put in those caches by hand, as SwiftLint would.
    @Test("A config another lint read before an edit isn't used after it", arguments: [true, false])
    func ignoresWhatAnotherLintCached(nested: Bool) async throws {
        let workspace = try makeWorkspace(config: nested ? nil : "parent_config: base.yml\n")
        let edited: URL
        if nested {
            let folder = workspace.appendingPathComponent("Nested", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Self.source.write(to: folder.appendingPathComponent("Inner.swift"), atomically: true, encoding: .utf8)
            edited = folder.appendingPathComponent(".swiftlint.yml")
        } else {
            edited = workspace.appendingPathComponent("base.yml")
        }
        try "opt_in_rules:\n  - \(Self.optInRule)\n".write(to: edited, atomically: true, encoding: .utf8)
        SwiftLintInProcessActor.prepare()
        try CurrentWorkingDirectory.$url.withValue(workspace) {
            let root = try InProcessConfiguration.root(configPath: nil, workspacePath: workspace).configuration
            for file in root.lintableFiles(inPath: workspace, forceExclude: false, excludeByPrefix: false) {
                _ = root.configuration(for: file)
            }
        }

        try "disabled_rules:\n  - trailing_newline\n".write(to: edited, atomically: true, encoding: .utf8)
        #expect(try await !ruleIDs(configPath: nil, workspace: workspace).contains(Self.optInRule))
    }

    // MARK: - Configs SwiftLint would end the process for

    @Test("A config pinned to another SwiftLint version is an error, not an exit", arguments: [true, false])
    func versionMismatchThrows(explicitConfig: Bool) async throws {
        let workspace = try makeWorkspace(config: "swiftlint_version: 0.0.1\n")
        let configPath = explicitConfig ? workspace.appendingPathComponent(".swiftlint.yml") : nil

        await #expect(throws: InProcessConfigurationError.self) {
            _ = try await ruleIDs(configPath: configPath, workspace: workspace)
        }
    }

    @Test("A config SwiftLint rejects is an error naming the file")
    func invalidRootConfigThrows() async throws {
        let workspace = try makeWorkspace(config: "only_rules:\n  - force_cast\ndisabled_rules:\n  - todo\n")

        let error = await #expect(throws: InProcessConfigurationError.self) {
            _ = try await ruleIDs(configPath: nil, workspace: workspace)
        }
        #expect(error?.localizedDescription.contains(".swiftlint.yml") == true)
    }

    /// SwiftLint takes a reference for remote only when it starts `http://` or `https://`, and
    /// ends the process for a local one pinned to another version.
    @Test("A local parent config whose name starts with http is checked like any other")
    func localParentNamedHTTPIsChecked() async throws {
        let workspace = try makeWorkspace(config: "parent_config: http-base.yml\n")
        try "swiftlint_version: 0.0.1\n"
            .write(to: workspace.appendingPathComponent("http-base.yml"), atomically: true, encoding: .utf8)

        await #expect(throws: InProcessConfigurationError.self) {
            _ = try await ruleIDs(configPath: nil, workspace: workspace)
        }
    }

    /// SwiftLint loads nested configs itself and ends the process if one is invalid.
    @Test("An invalid nested config is an error, not a crash", arguments: [
        "only_rules:\n  - force_cast\nopt_in_rules:\n  - empty_count\n",
        "swiftlint_version: 0.0.1\n"
    ])
    func invalidNestedConfigThrows(nestedConfig: String) async throws {
        let workspace = try makeWorkspace(config: nil)
        let nested = workspace.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Self.source.write(to: nested.appendingPathComponent("Inner.swift"), atomically: true, encoding: .utf8)
        try writeConfig(nestedConfig, in: nested)

        await #expect(throws: InProcessConfigurationError.self) {
            _ = try await ruleIDs(configPath: nil, workspace: workspace)
        }
    }

    @Test("A nested config is ignored when the lint names its config, like --config")
    func explicitConfigIgnoresNestedConfigs() async throws {
        let workspace = try makeWorkspace(config: "disabled_rules:\n  - trailing_newline\n")
        let nested = workspace.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Self.source.write(to: nested.appendingPathComponent("Inner.swift"), atomically: true, encoding: .utf8)
        try writeConfig("opt_in_rules:\n  - \(Self.optInRule)\n", in: nested)

        let configPath = workspace.appendingPathComponent(".swiftlint.yml")
        #expect(try await !ruleIDs(configPath: configPath, workspace: workspace).contains(Self.optInRule))
    }

    /// The subprocess backend's analysis runs `swiftlint lint` in the workspace without
    /// `--config` (its `.effective` mode), so the nested configs apply there.
    @Test("The workspace analysis applies nested configs beneath the workspace's config, as Studio's does")
    func analysisAppliesNestedConfigs() async throws {
        let workspace = try makeWorkspace(config: "disabled_rules:\n  - trailing_newline\n")
        let nested = workspace.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Self.source.write(to: nested.appendingPathComponent("Inner.swift"), atomically: true, encoding: .utf8)
        try writeConfig("opt_in_rules:\n  - \(Self.optInRule)\n", in: nested)
        #expect(try await analyzedRuleIDs(in: workspace).contains(Self.optInRule))

        // And as the rest of this suite shows for a lint with no config path, edits to the
        // nested config show on the next analysis.
        try writeConfig("disabled_rules:\n  - trailing_newline\n", in: nested)
        #expect(try await !analyzedRuleIDs(in: workspace).contains(Self.optInRule))
    }

    @Test("The workspace analysis reports what a lint with no config path does")
    func analysisMatchesLintWithoutConfigPath() async throws {
        let workspace = try makeWorkspace(config: "parent_config: base.yml\nopt_in_rules:\n  - force_unwrapping\n")
        try "opt_in_rules:\n  - \(Self.optInRule)\n"
            .write(to: workspace.appendingPathComponent("base.yml"), atomically: true, encoding: .utf8)
        let nested = workspace.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Self.source.write(to: nested.appendingPathComponent("Inner.swift"), atomically: true, encoding: .utf8)
        try writeConfig("disabled_rules:\n  - \(Self.optInRule)\n", in: nested)

        let analyzed = try await SwiftLintInProcessActor().executeLintCommand(
            configPath: workspace.appendingPathComponent(".swiftlint.yml"),
            workspacePath: workspace
        )
        let linted = try SwiftLintInProcessActor.lint(configPath: nil, workspacePath: workspace)
        #expect(analyzed == linted)
        #expect(try ruleIDs(in: analyzed).contains(Self.optInRule), "the root and its parent apply")
    }
}
