//
//  ResolvedConfigurationEngineTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for ResolvedConfigurationEngine — merging a workspace's nested
//  `.swiftlint.yml` layers into the effective config for a folder, with
//  per-decision attribution. Each test encodes a row of the merge-semantics
//  table in docs/nested-config-visibility.md.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct ResolvedConfigurationEngineTests {

    // MARK: - Helpers

    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResolvedConfigTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @discardableResult
    private func writeConfig(_ content: String, at relativeDirectory: String, in root: URL) throws -> URL {
        let directory = relativeDirectory.isEmpty
            ? root
            : root.appendingPathComponent(relativeDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configPath = directory.appendingPathComponent(".swiftlint.yml")
        try content.write(to: configPath, atomically: true, encoding: .utf8)
        return configPath
    }

    private func cleanup(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    /// Workspace mirroring the doc's running example:
    /// - root: opts in force_unwrapping, configures line_length, sets excluded /
    ///   reporter / analyzer_rules
    /// - Tests: disables force_try + force_unwrapping, sets a (nested, ignored)
    ///   excluded
    /// - Sources/Legacy: overrides line_length
    private func makeLayeredWorkspace() throws -> URL {
        let root = try makeWorkspace()
        try writeConfig(
            """
            opt_in_rules:
              - force_unwrapping
            analyzer_rules:
              - unused_declaration
            excluded:
              - Generated
            reporter: "xcode"
            line_length:
              warning: 120
            """,
            at: "",
            in: root
        )
        try writeConfig(
            """
            disabled_rules:
              - force_try
              - force_unwrapping
            excluded:
              - IgnoredInTests.swift
            """,
            at: "Tests",
            in: root
        )
        try writeConfig("line_length:\n  warning: 200\n", at: "Sources/Legacy", in: root)
        return root
    }

    private func resolve(at relativeDirectory: String, in root: URL) -> ResolvedConfiguration {
        let directory = relativeDirectory.isEmpty
            ? root
            : root.appendingPathComponent(relativeDirectory, isDirectory: true)
        let tree = ConfigTreeDiscovery().discover(in: root)
        return ResolvedConfigurationEngine().resolve(at: directory, in: tree)
    }

    // MARK: - Inheritance into a config-less folder

    @Test("a folder with no config inherits the root layer")
    @MainActor
    func testInheritsRootForConfiglessFolder() throws {
        let root = try makeLayeredWorkspace()
        defer { cleanup(root) }

        let resolved = resolve(at: "Sources/Feature", in: root)

        #expect(resolved.layerChain.map(\.displayName) == ["root"])
        #expect(resolved.disabledRules.isEmpty)
        #expect(resolved.optInRules.map(\.identifier) == ["force_unwrapping"])
        #expect(resolved.optInRules.first?.setBy.isRoot == true)
        #expect(resolved.reporter?.value == "xcode")
        #expect(resolved.analyzerRules.map(\.identifier) == ["unused_declaration"])
    }

    // MARK: - disabled / opt-in accumulation + attribution

    @Test("nested disabled_rules accumulate and attribute to the disabling layer")
    @MainActor
    func testDisabledAccumulationAndAttribution() throws {
        let root = try makeLayeredWorkspace()
        defer { cleanup(root) }

        let resolved = resolve(at: "Tests", in: root)

        #expect(resolved.layerChain.map(\.displayName) == ["root", "Tests"])

        let disabledIdentifiers = Set(resolved.disabledRules.map(\.identifier))
        #expect(disabledIdentifiers == ["force_try", "force_unwrapping"])

        // force_unwrapping was opted-in at root, then disabled by Tests → its
        // final state is "disabled, set by Tests", and it is no longer opted-in.
        #expect(resolved.disablingLayer(for: "force_unwrapping")?.displayName == "Tests")
        #expect(resolved.optInRules.contains { $0.identifier == "force_unwrapping" } == false)
    }

    // MARK: - rule configuration override + previous value

    @Test("a deeper layer overrides a rule config and records the prior value")
    @MainActor
    func testRuleConfigurationOverride() throws {
        let root = try makeLayeredWorkspace()
        defer { cleanup(root) }

        let atLegacy = resolve(at: "Sources/Legacy", in: root)
        let legacyLineLength = try #require(atLegacy.configuration(for: "line_length"))
        #expect(legacyLineLength.setBy.displayName == "Legacy")
        #expect(legacyLineLength.overridesAncestor)
        #expect(legacyLineLength.previousSetBy?.isRoot == true)
        #expect(legacyLineLength.configuration != legacyLineLength.previousConfiguration)

        let atRoot = resolve(at: "", in: root)
        let rootLineLength = try #require(atRoot.configuration(for: "line_length"))
        #expect(rootLineLength.setBy.isRoot == true)
        #expect(rootLineLength.overridesAncestor == false)
    }

    // MARK: - excluded is root-only (the trap)

    @Test("excluded is honored only from the root; nested excluded is ignored")
    @MainActor
    func testExcludedIsRootOnly() throws {
        let root = try makeLayeredWorkspace()
        defer { cleanup(root) }

        let resolved = resolve(at: "Tests", in: root)

        let excluded = try #require(resolved.excluded)
        #expect(excluded.value == ["Generated"])
        #expect(excluded.setBy.isRoot == true)
        // The Tests-layer `excluded: [IgnoredInTests.swift]` must NOT appear.
        #expect(excluded.value.contains("IgnoredInTests.swift") == false)
    }

    // MARK: - only_rules hard reset

    @Test("only_rules in a nested layer hard-resets the subtree")
    @MainActor
    func testOnlyRulesHardReset() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig("opt_in_rules:\n  - empty_count\n", at: "", in: root)
        try writeConfig("only_rules:\n  - todo\n  - line_length\n", at: "Sub", in: root)

        let atSub = resolve(at: "Sub", in: root)
        #expect(atSub.isOnlyRulesMode)
        #expect(atSub.onlyRules?.value == ["line_length", "todo"])
        #expect(atSub.onlyRules?.setBy.displayName == "Sub")

        let atRoot = resolve(at: "", in: root)
        #expect(atRoot.isOnlyRulesMode == false)
    }
}
