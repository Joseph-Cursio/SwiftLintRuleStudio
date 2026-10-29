//
//  ConfigTreeDiscoveryRootGraphTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Which discovered configs the root config pulls in with `parent_config` and
//  `child_config`, and where each sits in the chain SwiftLint merges into the root
//  configuration.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct ConfigTreeDiscoveryRootGraphTests {
    /// A workspace holding `configs`, each a `.swiftlint.yml` keyed by its folder
    /// relative to the workspace (`""` for the root).
    private static func workspace(_ configs: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigTreeDiscoveryRootGraphTests-\(UUID().uuidString)", isDirectory: true)
        for (relative, content) in configs {
            let directory = relative.isEmpty ? root : root.appendingPathComponent(relative, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try content.write(to: directory.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        }
        return root
    }

    private static func positions(in tree: ConfigTree) -> [String: Int] {
        tree.configs.reduce(into: [:]) { positions, config in
            positions[config.relativePath] = config.rootGraphPosition
        }
    }

    @Test("parent_config is followed up from the root and child_config down, each relative to its own config")
    func followsBothChains() throws {
        let root = try Self.workspace([
            "": "parent_config: Base/.swiftlint.yml\nchild_config: Overrides/.swiftlint.yml\n",
            "Base": "parent_config: ../Shared/.swiftlint.yml\n",
            "Shared": "disabled_rules: [todo]\n",
            "Overrides": "child_config: Strict/.swiftlint.yml\n",
            "Overrides/Strict": "opt_in_rules: [empty_count]\n",
            "Elsewhere": "disabled_rules: [force_cast]\n"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = ConfigTreeDiscovery().discover(in: root)

        #expect(Self.positions(in: tree) == [
            "Shared/.swiftlint.yml": -2,
            "Base/.swiftlint.yml": -1,
            "Overrides/.swiftlint.yml": 1,
            "Overrides/Strict/.swiftlint.yml": 2
        ])
        #expect(tree.rootGraph.map(\.relativePath) == [
            "Shared/.swiftlint.yml",
            "Base/.swiftlint.yml",
            ".swiftlint.yml",
            "Overrides/.swiftlint.yml",
            "Overrides/Strict/.swiftlint.yml"
        ])
    }

    @Test("a nested config's own references, remote ones, and files that aren't discovered configs are not followed")
    func followsOnlyTheRootsLocalReferences() throws {
        let root = try Self.workspace([
            "": "child_config: Shared/custom.yml\nparent_config: https://example.com/.swiftlint.yml\n",
            "Shared": "disabled_rules: [todo]\n",
            "Sub": "child_config: ../Other/.swiftlint.yml\n",
            "Other": "disabled_rules: [force_cast]\n"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = ConfigTreeDiscovery().discover(in: root)

        #expect(Self.positions(in: tree).isEmpty)
        #expect(tree.rootGraph.map(\.relativePath) == [".swiftlint.yml"])
    }

    @Test("with no root config, nothing is pulled in")
    func noRootNoGraph() throws {
        let root = try Self.workspace([
            "Sub": "child_config: ../Other/.swiftlint.yml\n",
            "Other": "disabled_rules: [force_cast]\n"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = ConfigTreeDiscovery().discover(in: root)

        #expect(tree.rootGraph.isEmpty)
        #expect(Self.positions(in: tree).isEmpty)
    }

    @Test("excluded in a config the root pulls in is not flagged as ignored, as in any other nested config")
    func pulledInExclusionsAreEffective() throws {
        let root = try Self.workspace([
            "": "child_config: Shared/.swiftlint.yml\n",
            "Shared": "excluded:\n  - Generated\n",
            "Sub": "excluded:\n  - Generated\n"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = ConfigTreeDiscovery().discover(in: root)

        #expect(tree.configsWithIneffectiveExclusions.map(\.relativePath) == ["Sub/.swiftlint.yml"])
    }
}
