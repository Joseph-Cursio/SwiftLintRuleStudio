//
//  SimulationWorkspaceBuilderTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Unit tests for the non-destructive shadow workspace: mirroring of sources and
//  enabling a rule across the root + nested configs. No real swiftlint needed.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct SimulationWorkspaceBuilderTests {

    // MARK: - Helpers

    private func makeTempWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowBuilderTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadConfig(at url: URL) throws -> YAMLConfigurationEngine.YAMLConfig {
        let engine = YAMLConfigurationEngine(configPath: url)
        try engine.load()
        return engine.getConfig()
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Mirroring

    @Test("mirrors .swift files at their relative paths, build directories too")
    func mirrorsSwiftFilesAndSkipsBuildDirectory() throws {
        let workspaceRoot = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        try write("let a = 1\n", to: workspaceRoot.appendingPathComponent("Sources/A.swift"))
        try write("let b = 2\n", to: workspaceRoot.appendingPathComponent("Tests/B.swift"))
        // SwiftLint lints build directories unless the config excludes them, and so must the
        // mirror; the config's `excluded` decides there as it does in the workspace.
        try write("let c = 3\n", to: workspaceRoot.appendingPathComponent(".build/checkouts/C.swift"))

        let workspace = Workspace(path: workspaceRoot)
        let shadow = try SimulationWorkspaceBuilder().makeWorkspace(for: workspace, baseConfigPath: nil)
        defer { shadow.cleanup() }

        #expect(fileExists(shadow.root.appendingPathComponent("Sources/A.swift")))
        #expect(fileExists(shadow.root.appendingPathComponent("Tests/B.swift")))
        #expect(fileExists(shadow.root.appendingPathComponent(".build/checkouts/C.swift")))

        // Mirrored content matches the original.
        let mirrored = try String(
            contentsOf: shadow.root.appendingPathComponent("Sources/A.swift"),
            encoding: .utf8
        )
        #expect(mirrored == "let a = 1\n")
    }

    // MARK: - Enabling the rule as Enable does

    @Test("enables the rule in the root config, and leaves nested configs as they are")
    func enablesRuleInRootAndNestedConfigs() throws {
        let workspaceRoot = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        try write("disabled_rules:\n  - force_cast\n", to: workspaceRoot.appendingPathComponent(".swiftlint.yml"))
        // A nested config that disables the same rule for its subtree.
        try write(
            "disabled_rules:\n  - force_cast\n",
            to: workspaceRoot.appendingPathComponent("Legacy/.swiftlint.yml")
        )
        try write("let a = 1\n", to: workspaceRoot.appendingPathComponent("Legacy/A.swift"))

        let workspace = Workspace(path: workspaceRoot)
        let shadow = try SimulationWorkspaceBuilder().makeWorkspace(for: workspace, baseConfigPath: nil)
        defer { shadow.cleanup() }

        try shadow.applyRule("force_cast", isOptIn: false, isAnalyzer: false, parameterOverrides: nil)

        // A default rule is "on" unless disabled, so the signal that it will fire
        // is its removal from disabled_rules (an enabled entry with no severity or
        // parameters is collapsed away on serialization, so `rules[...]` is nil).
        let rootConfig = try loadConfig(at: shadow.root.appendingPathComponent(".swiftlint.yml"))
        #expect(rootConfig.disabledRules?.contains("force_cast") != true)

        // Nested: Enable writes only the root config, so the subtree's opt-out stays.
        let nestedConfig = try loadConfig(at: shadow.root.appendingPathComponent("Legacy/.swiftlint.yml"))
        #expect(nestedConfig.disabledRules == ["force_cast"])
    }

    @Test("leaves a nested only_rules whitelist as it is")
    func appendsRuleToNestedOnlyRules() throws {
        let workspaceRoot = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        try write("", to: workspaceRoot.appendingPathComponent(".swiftlint.yml"))
        try write("only_rules:\n  - line_length\n", to: workspaceRoot.appendingPathComponent("Sub/.swiftlint.yml"))

        let workspace = Workspace(path: workspaceRoot)
        let shadow = try SimulationWorkspaceBuilder().makeWorkspace(for: workspace, baseConfigPath: nil)
        defer { shadow.cleanup() }

        try shadow.applyRule("force_cast", isOptIn: false, isAnalyzer: false, parameterOverrides: nil)

        // Enable doesn't touch it, so beneath it the rule stays off.
        let nestedConfig = try loadConfig(at: shadow.root.appendingPathComponent("Sub/.swiftlint.yml"))
        #expect(nestedConfig.onlyRules == ["line_length"])
    }

    @Test("an opt-in rule goes in only_rules alone when there is one, which SwiftLint requires")
    func optInRuleUnderOnlyRulesSkipsOptInList() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.onlyRules = ["line_length"]

        ConfigRuleEnabler.enableRule("empty_count", in: &config, isOptIn: true, isAnalyzer: false)

        #expect(config.onlyRules == ["line_length", "empty_count"])
        #expect(config.optInRules == nil)
    }

    @Test("preserves relative excluded/included entries verbatim in the mirror")
    func preservesExcludedAndIncludedVerbatim() throws {
        let workspaceRoot = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        try write(
            "included:\n  - Sources\nexcluded:\n  - Sources/Generated\n",
            to: workspaceRoot.appendingPathComponent(".swiftlint.yml")
        )

        let workspace = Workspace(path: workspaceRoot)
        let shadow = try SimulationWorkspaceBuilder().makeWorkspace(for: workspace, baseConfigPath: nil)
        defer { shadow.cleanup() }

        try shadow.applyRule("force_cast", isOptIn: false, isAnalyzer: false, parameterOverrides: nil)

        let rootConfig = try loadConfig(at: shadow.root.appendingPathComponent(".swiftlint.yml"))
        #expect(rootConfig.included == ["Sources"])
        #expect(rootConfig.excluded == ["Sources/Generated"])
    }

    @Test("seeds a root config when the workspace has none")
    func seedsRootConfigWhenWorkspaceHasNone() throws {
        let workspaceRoot = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        try write("let a = 1\n", to: workspaceRoot.appendingPathComponent("Sources/A.swift"))

        let workspace = Workspace(path: workspaceRoot)
        let shadow = try SimulationWorkspaceBuilder().makeWorkspace(for: workspace, baseConfigPath: nil)
        defer { shadow.cleanup() }

        try shadow.applyRule("explicit_init", isOptIn: true, isAnalyzer: false, parameterOverrides: nil)

        let rootConfigURL = shadow.root.appendingPathComponent(".swiftlint.yml")
        #expect(fileExists(rootConfigURL))
        let rootConfig = try loadConfig(at: rootConfigURL)
        #expect(rootConfig.optInRules?.contains("explicit_init") == true)
    }

    @Test("applyRule starts fresh each call, so a prior rule does not leak")
    func applyRuleDoesNotLeakBetweenCalls() throws {
        let workspaceRoot = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        try write("", to: workspaceRoot.appendingPathComponent(".swiftlint.yml"))

        let workspace = Workspace(path: workspaceRoot)
        let shadow = try SimulationWorkspaceBuilder().makeWorkspace(for: workspace, baseConfigPath: nil)
        defer { shadow.cleanup() }

        try shadow.applyRule("force_cast", isOptIn: false, isAnalyzer: false, parameterOverrides: nil)
        try shadow.applyRule("explicit_init", isOptIn: true, isAnalyzer: false, parameterOverrides: nil)

        // The second call rebuilds from the original config, so force_cast from
        // the first call is gone — batch audits must not accumulate rules.
        let rootConfig = try loadConfig(at: shadow.root.appendingPathComponent(".swiftlint.yml"))
        #expect(rootConfig.optInRules?.contains("explicit_init") == true)
        #expect(rootConfig.rules["force_cast"] == nil)
    }

    /// SwiftLint run in-process caches configs by path, so a batch audit that lints the
    /// same paths for every rule would measure later rules with earlier rules' configs.
    @Test("applyRule moves the mirror to a new path each call, taking its files along")
    func applyRuleMovesTheMirror() throws {
        let workspaceRoot = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        try write("let a = 1\n", to: workspaceRoot.appendingPathComponent("Sources/A.swift"))
        try write("disabled_rules:\n  - todo\n", to: workspaceRoot.appendingPathComponent("Sub/.swiftlint.yml"))

        let workspace = Workspace(path: workspaceRoot)
        let shadow = try SimulationWorkspaceBuilder().makeWorkspace(for: workspace, baseConfigPath: nil)
        defer { shadow.cleanup() }

        try shadow.applyRule("force_cast", isOptIn: false, isAnalyzer: false, parameterOverrides: nil)
        let firstRoot = shadow.root
        try shadow.applyRule("todo", isOptIn: false, isAnalyzer: false, parameterOverrides: nil)

        #expect(shadow.root != firstRoot)
        #expect(!fileExists(firstRoot), "the old path is gone, not copied")
        #expect(fileExists(shadow.root.appendingPathComponent("Sources/A.swift")))
        #expect(fileExists(shadow.root.appendingPathComponent("Sub/.swiftlint.yml")))
    }

    @Test("cleanup removes the mirror wherever it has moved to")
    func cleanupRemovesTheMovedMirror() throws {
        let workspaceRoot = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        let workspace = Workspace(path: workspaceRoot)
        let shadow = try SimulationWorkspaceBuilder().makeWorkspace(for: workspace, baseConfigPath: nil)
        try shadow.applyRule("force_cast", isOptIn: false, isAnalyzer: false, parameterOverrides: nil)
        let movedRoot = shadow.root
        shadow.cleanup()

        #expect(!fileExists(movedRoot))
    }
}
