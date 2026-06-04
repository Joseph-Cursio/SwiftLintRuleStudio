//
//  ConfigTreeDiscoveryTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for ConfigTreeDiscovery — walking a workspace for nested
//  `.swiftlint.yml` files and linking them into a ConfigTree.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct ConfigTreeDiscoveryTests {

    // MARK: - Helpers

    /// Creates a fresh temp workspace root.
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigTreeTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Writes `content` to `<root>/<relativeDirectory>/.swiftlint.yml`.
    @discardableResult
    private func writeConfig(
        _ content: String,
        at relativeDirectory: String,
        in root: URL
    ) throws -> URL {
        let directory = relativeDirectory.isEmpty
            ? root
            : root.appendingPathComponent(relativeDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configPath = directory.appendingPathComponent(".swiftlint.yml")
        try content.write(to: configPath, atomically: true, encoding: .utf8)
        return configPath
    }

    private func writeFile(_ content: String, at relativePath: String, in root: URL) throws {
        let fileURL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func cleanup(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    /// Builds a representative workspace:
    /// - root config: opt-in force_unwrapping, line_length, excluded (effective)
    /// - Tests: disables force_try + force_unwrapping
    /// - Sources/Legacy: disables line_length
    /// - Sources/Generated: nested `excluded` (ineffective — the trap)
    /// - .build: a config that must be excluded from discovery
    /// - Sources/Feature: a Swift file but NO config (must not be a node)
    private func makePopulatedWorkspace() throws -> URL {
        let root = try makeWorkspace()
        try writeConfig(
            """
            opt_in_rules:
              - force_unwrapping
            excluded:
              - Generated
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
            """,
            at: "Tests",
            in: root
        )
        try writeConfig("disabled_rules:\n  - line_length\n", at: "Sources/Legacy", in: root)
        try writeConfig("excluded:\n  - Ignored.swift\n", at: "Sources/Generated", in: root)
        try writeConfig("disabled_rules:\n  - todo\n", at: ".build/checkouts/Dep", in: root)
        try writeFile("let value = 1\n", at: "Sources/Feature/Feature.swift", in: root)
        return root
    }

    // MARK: - File discovery

    @Test("configFileURLs finds nested configs and skips build directories")
    @MainActor
    func testConfigFileDiscoverySkipsBuildDirs() throws {
        let root = try makePopulatedWorkspace()
        defer { cleanup(root) }

        let urls = ConfigTreeDiscovery.configFileURLs(in: root)
        let relativeDirs = Set(urls.map {
            $0.deletingLastPathComponent().lastPathComponent
        })

        #expect(urls.count == 4)
        #expect(relativeDirs.contains("Tests"))
        #expect(relativeDirs.contains("Legacy"))
        #expect(relativeDirs.contains("Generated"))
        // The config under .build/checkouts/Dep must be pruned.
        #expect(relativeDirs.contains("Dep") == false)
        #expect(urls.allSatisfy { $0.path.contains("/.build/") } == false)
    }

    // MARK: - Tree structure

    @Test("discover builds the tree with correct depth and relative paths")
    @MainActor
    func testDiscoverTreeStructure() throws {
        let root = try makePopulatedWorkspace()
        defer { cleanup(root) }

        let tree = ConfigTreeDiscovery().discover(in: root)

        #expect(tree.configs.count == 4)

        let rootConfig = try #require(tree.rootConfig)
        #expect(rootConfig.isRoot)
        #expect(rootConfig.depth == 0)
        #expect(rootConfig.relativePath == ".swiftlint.yml")

        let byRelative = Dictionary(
            uniqueKeysWithValues: tree.configs.map { ($0.relativePath, $0) }
        )
        let testsConfig = try #require(byRelative["Tests/.swiftlint.yml"])
        let legacyConfig = try #require(byRelative["Sources/Legacy/.swiftlint.yml"])

        #expect(testsConfig.depth == 1)
        #expect(testsConfig.isRoot == false)
        #expect(legacyConfig.depth == 2)
    }

    @Test("discover links each nested config to its nearest ancestor config")
    @MainActor
    func testDiscoverParentLinks() throws {
        let root = try makePopulatedWorkspace()
        defer { cleanup(root) }

        let tree = ConfigTreeDiscovery().discover(in: root)
        let rootConfig = try #require(tree.rootConfig)
        let byRelative = Dictionary(
            uniqueKeysWithValues: tree.configs.map { ($0.relativePath, $0) }
        )

        let testsConfig = try #require(byRelative["Tests/.swiftlint.yml"])
        let legacyConfig = try #require(byRelative["Sources/Legacy/.swiftlint.yml"])

        // Sources/ has no config of its own, so Legacy's nearest ancestor is root.
        #expect(testsConfig.parentID == rootConfig.id)
        #expect(legacyConfig.parentID == rootConfig.id)
        #expect(rootConfig.parentID == nil)
        #expect(tree.children(of: rootConfig).count == 3)
    }

    // MARK: - Summaries

    @Test("discover summarizes what each config declares")
    @MainActor
    func testDiscoverSummaries() throws {
        let root = try makePopulatedWorkspace()
        defer { cleanup(root) }

        let tree = ConfigTreeDiscovery().discover(in: root)
        let byRelative = Dictionary(
            uniqueKeysWithValues: tree.configs.map { ($0.relativePath, $0) }
        )

        let rootConfig = try #require(tree.rootConfig)
        let testsConfig = try #require(byRelative["Tests/.swiftlint.yml"])

        #expect(testsConfig.summary.disabledRuleCount == 2)
        #expect(rootConfig.summary.optInRuleCount == 1)
        #expect(rootConfig.summary.setsExcluded)
    }

    // MARK: - The `excluded` trap

    @Test("nested excluded is flagged ineffective; root excluded is not")
    @MainActor
    func testIneffectiveNestedExclusions() throws {
        let root = try makePopulatedWorkspace()
        defer { cleanup(root) }

        let tree = ConfigTreeDiscovery().discover(in: root)
        let byRelative = Dictionary(
            uniqueKeysWithValues: tree.configs.map { ($0.relativePath, $0) }
        )

        let rootConfig = try #require(tree.rootConfig)
        let generatedConfig = try #require(byRelative["Sources/Generated/.swiftlint.yml"])

        #expect(generatedConfig.hasIneffectiveExclusions)
        #expect(rootConfig.hasIneffectiveExclusions == false)

        let flagged = tree.configsWithIneffectiveExclusions.map(\.relativePath)
        #expect(flagged == ["Sources/Generated/.swiftlint.yml"])
    }

    // MARK: - No root config

    @Test("discover handles a workspace whose only config is nested")
    @MainActor
    func testDiscoverWithoutRootConfig() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig("disabled_rules:\n  - todo\n", at: "Sub", in: root)

        let tree = ConfigTreeDiscovery().discover(in: root)

        #expect(tree.rootConfig == nil)
        #expect(tree.configs.count == 1)
        let only = try #require(tree.configs.first)
        #expect(only.isRoot == false)
        #expect(only.depth == 1)
        #expect(only.parentID == nil)
    }
}
