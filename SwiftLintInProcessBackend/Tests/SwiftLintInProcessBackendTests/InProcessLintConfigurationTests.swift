import Foundation
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

    private func ruleIDs(configPath: URL?, workspace: URL) async throws -> Set<String> {
        let data = try await SwiftLintInProcessActor().executeLintCommand(
            configPath: configPath,
            workspacePath: workspace
        )
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
}
