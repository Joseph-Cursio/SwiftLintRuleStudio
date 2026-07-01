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

    @Test("mirrors .swift files at their relative paths and skips build directories")
    func mirrorsSwiftFilesAndSkipsBuildDirectory() throws {
        let workspaceRoot = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        try write("let a = 1\n", to: workspaceRoot.appendingPathComponent("Sources/A.swift"))
        try write("let b = 2\n", to: workspaceRoot.appendingPathComponent("Tests/B.swift"))
        // Build artifacts must never be mirrored (they'd inflate the counts).
        try write("let c = 3\n", to: workspaceRoot.appendingPathComponent(".build/checkouts/C.swift"))

        let workspace = Workspace(path: workspaceRoot)
        let shadow = try SimulationWorkspaceBuilder().makeWorkspace(for: workspace, baseConfigPath: nil)
        defer { shadow.cleanup() }

        #expect(fileExists(shadow.root.appendingPathComponent("Sources/A.swift")))
        #expect(fileExists(shadow.root.appendingPathComponent("Tests/B.swift")))
        #expect(fileExists(shadow.root.appendingPathComponent(".build/checkouts/C.swift")) == false)

        // Mirrored content matches the original.
        let mirrored = try String(
            contentsOf: shadow.root.appendingPathComponent("Sources/A.swift"),
            encoding: .utf8
        )
        #expect(mirrored == "let a = 1\n")
    }

    // MARK: - Enabling the rule everywhere

    @Test("enables the rule in the root and every nested config")
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

        // Nested: the subtree's opt-out is overridden too (the "merge into every
        // nested config" semantic).
        let nestedConfig = try loadConfig(at: shadow.root.appendingPathComponent("Legacy/.swiftlint.yml"))
        #expect(nestedConfig.disabledRules?.contains("force_cast") != true)
    }

    @Test("appends the rule to a nested only_rules whitelist")
    func appendsRuleToNestedOnlyRules() throws {
        let workspaceRoot = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        try write("", to: workspaceRoot.appendingPathComponent(".swiftlint.yml"))
        try write("only_rules:\n  - line_length\n", to: workspaceRoot.appendingPathComponent("Sub/.swiftlint.yml"))

        let workspace = Workspace(path: workspaceRoot)
        let shadow = try SimulationWorkspaceBuilder().makeWorkspace(for: workspace, baseConfigPath: nil)
        defer { shadow.cleanup() }

        try shadow.applyRule("force_cast", isOptIn: false, isAnalyzer: false, parameterOverrides: nil)

        let nestedConfig = try loadConfig(at: shadow.root.appendingPathComponent("Sub/.swiftlint.yml"))
        #expect(nestedConfig.onlyRules?.contains("force_cast") == true)
        #expect(nestedConfig.onlyRules?.contains("line_length") == true)
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
}
