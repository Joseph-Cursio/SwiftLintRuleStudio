//
//  ConfigMapPresenterTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for ConfigMapPresenter — building the sparse Config Tree rows and the
//  resolved-config inspector display from the discovery/resolution engines.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct ConfigMapPresenterTests {

    // MARK: - Helpers

    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigMapTests", isDirectory: true)
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

    /// root (opt-in + excluded + line_length), Tests (disables 2), Sources/Legacy
    /// (overrides line_length), plus a config-less Sources/Feature folder.
    private func makeLayeredWorkspace() throws -> URL {
        let root = try makeWorkspace()
        try writeConfig(
            "opt_in_rules:\n  - force_unwrapping\nexcluded:\n  - Generated\nline_length:\n  warning: 120\n",
            at: "",
            in: root
        )
        try writeConfig("disabled_rules:\n  - force_try\n  - force_unwrapping\n", at: "Tests", in: root)
        try writeConfig("line_length:\n  warning: 200\n", at: "Sources/Legacy", in: root)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources/Feature", isDirectory: true),
            withIntermediateDirectories: true
        )
        return root
    }

    private func tree(in root: URL) -> ConfigTree {
        ConfigTreeDiscovery().discover(in: root)
    }

    // MARK: - Sparse tree rows

    @Test("treeRows are pre-order with config-tree indentation and badges")
    @MainActor
    func testTreeRows() throws {
        let root = try makeLayeredWorkspace()
        defer { cleanup(root) }

        let rows = ConfigMapPresenter().treeRows(for: tree(in: root))

        // Sources/ has no config, so Legacy sits one level under root (not two).
        #expect(rows.map(\.displayName) == ["root", "Legacy", "Tests"])
        #expect(rows.map(\.indentLevel) == [0, 1, 1])
        #expect(rows.first?.isRoot == true)

        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.displayName, $0) })
        #expect(byName["Tests"]?.badge == "-2 disabled")
        #expect(byName["root"]?.badge == "+1 opt-in, 1 configured")
        #expect(byName["Legacy"]?.badge == "1 configured")
    }

    @Test("badge reflects only_rules and parse-error states")
    @MainActor
    func testBadgeSpecialStates() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig("only_rules:\n  - todo\n  - line_length\n", at: "", in: root)
        try writeConfig("excluded:\n  - X.swift\n", at: "Nested", in: root)

        let rows = ConfigMapPresenter().treeRows(for: tree(in: root))
        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.displayName, $0) })

        #expect(byName["root"]?.badge == "only 2 rules")
        // A nested config that only sets excluded changes no rules and is flagged.
        #expect(byName["Nested"]?.badge == "config only")
        #expect(byName["Nested"]?.hasIneffectiveExclusions == true)
    }

    // MARK: - Resolved inspector display

    @Test("display shows the layer chain, disabled rules, and excluded notice")
    @MainActor
    func testDisplayAtNestedFolder() throws {
        let root = try makeLayeredWorkspace()
        defer { cleanup(root) }
        let configTree = tree(in: root)
        let resolved = ResolvedConfigurationEngine().resolve(
            at: root.appendingPathComponent("Tests", isDirectory: true),
            in: configTree
        )

        let display = ConfigMapPresenter().display(for: resolved, in: configTree)

        #expect(display.targetLabel == "Tests")
        #expect(display.layerChainLabels == ["root", "Tests"])
        #expect(display.inheritsNotice == nil)

        let byRule = Dictionary(uniqueKeysWithValues: display.ruleRows.map { ($0.id, $0) })
        #expect(byRule["force_unwrapping"]?.state == "off (disabled)")
        #expect(byRule["force_unwrapping"]?.setBy == "Tests")

        let excluded = try #require(display.excludedNotice)
        #expect(excluded.contains("root"))
        #expect(excluded.contains("Generated"))
    }

    @Test("display reports inheritance for a folder with no config")
    @MainActor
    func testDisplayInheritsForConfiglessFolder() throws {
        let root = try makeLayeredWorkspace()
        defer { cleanup(root) }
        let configTree = tree(in: root)
        let resolved = ResolvedConfigurationEngine().resolve(
            at: root.appendingPathComponent("Sources/Feature", isDirectory: true),
            in: configTree
        )

        let display = ConfigMapPresenter().display(for: resolved, in: configTree)

        #expect(display.layerChainLabels == ["root"])
        let inherits = try #require(display.inheritsNotice)
        #expect(inherits.contains("root"))
    }

    @Test("display shows an override detail and only_rules notice")
    @MainActor
    func testDisplayOverrideAndOnlyRules() throws {
        let root = try makeLayeredWorkspace()
        defer { cleanup(root) }
        let configTree = tree(in: root)

        let atLegacy = ConfigMapPresenter().display(
            for: ResolvedConfigurationEngine().resolve(
                at: root.appendingPathComponent("Sources/Legacy", isDirectory: true),
                in: configTree
            ),
            in: configTree
        )
        let lineLength = try #require(atLegacy.ruleRows.first { $0.id == "line_length" })
        #expect(lineLength.state == "configured")
        #expect(lineLength.setBy == "Legacy")
        #expect(lineLength.detail == "overrides root")

        // only_rules notice in a separate workspace.
        let onlyRoot = try makeWorkspace()
        defer { cleanup(onlyRoot) }
        try writeConfig("disabled_rules:\n  - todo\n", at: "", in: onlyRoot)
        try writeConfig("only_rules:\n  - todo\n", at: "Sub", in: onlyRoot)
        let onlyTree = tree(in: onlyRoot)
        let atSub = ConfigMapPresenter().display(
            for: ResolvedConfigurationEngine().resolve(
                at: onlyRoot.appendingPathComponent("Sub", isDirectory: true),
                in: onlyTree
            ),
            in: onlyTree
        )
        let notice = try #require(atSub.onlyRulesNotice)
        #expect(notice.contains("Sub"))
    }
}
