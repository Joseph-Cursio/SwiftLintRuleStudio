//
//  ConfigMapPresenterTests+NearestConfig.swift
//  SwiftLintRuleStudioCoreTests
//
//  The Config Map's account of the nested configs that don't apply to a folder. SwiftLint
//  merges the root config with the nearest nested config alone, so a config in a folder between
//  them is passed over; the Config Map says so rather than leave the chain `root ▸ Deeper` to
//  look like an oversight.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

extension ConfigMapPresenterTests {
    /// The root opts in `empty_count`, `Sub` disables it, and `Sub/Deeper` disables `force_cast`.
    private func makeThreeLevelWorkspace() throws -> URL {
        let root = try makeWorkspace()
        try writeConfig("opt_in_rules:\n  - empty_count\n", at: "", in: root)
        try writeConfig("disabled_rules:\n  - empty_count\n", at: "Sub", in: root)
        try writeConfig("disabled_rules:\n  - force_cast\n", at: "Sub/Deeper", in: root)
        return root
    }

    private func display(at folder: String, in root: URL) -> ResolvedConfigDisplay {
        let configTree = tree(in: root)
        let resolved = ResolvedConfigurationEngine().resolve(
            at: root.appendingPathComponent(folder, isDirectory: true),
            in: configTree
        )
        return ConfigMapPresenter().display(for: resolved, in: configTree)
    }

    @Test("the inspector names the nested config above a folder that doesn't apply there")
    @MainActor
    func testSkippedNotice() throws {
        let root = try makeThreeLevelWorkspace()
        defer { cleanup(root) }

        let atDeeper = display(at: "Sub/Deeper", in: root)
        #expect(atDeeper.layerChainLabels == ["root", "Deeper"])
        #expect(
            atDeeper.skippedNotice == "Sub's config doesn't apply here — SwiftLint applies only the root config "
                + "and the nearest nested config, Deeper."
        )
        let emptyCount = try #require(atDeeper.ruleRows.first { $0.id == "empty_count" })
        #expect(emptyCount.state == "on (opt-in)")
        #expect(emptyCount.setBy == "root")

        // Beneath Deeper, a folder with no config of its own takes Deeper's place in the chain.
        let atPlain = display(at: "Sub/Deeper/Plain", in: root)
        #expect(atPlain.inheritsNotice == "No config in this folder — it inherits from Deeper.")
        #expect(atPlain.skippedNotice == atDeeper.skippedNotice)

        #expect(display(at: "Sub", in: root).skippedNotice == nil)
    }

    @Test("the notice names every config passed over, and no root config where there is none")
    @MainActor
    func testSkippedNoticeWithoutRoot() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig("disabled_rules:\n  - todo\n", at: "A", in: root)
        try writeConfig("disabled_rules:\n  - force_try\n", at: "A/B", in: root)
        try writeConfig("disabled_rules:\n  - force_cast\n", at: "A/B/C", in: root)

        #expect(
            display(at: "A/B/C", in: root).skippedNotice
                == "The configs in A and B don't apply here — SwiftLint applies only the nearest nested config, C."
        )
    }

    @Test("a tree row nested under another nested config's row says which config it replaces")
    @MainActor
    func testTreeRowsSayWhatTheyReplace() throws {
        let root = try makeThreeLevelWorkspace()
        defer { cleanup(root) }
        try writeConfig("disabled_rules:\n  - todo\n", at: "Other", in: root)

        let rows = ConfigMapPresenter().treeRows(for: tree(in: root))

        // Folders still nest the rows; only a row under a nested config's row replaces it.
        #expect(rows.map(\.displayName) == ["root", "Other", "Sub", "Deeper"])
        #expect(rows.map(\.indentLevel) == [0, 1, 1, 2])
        #expect(rows.map(\.replaces) == [nil, nil, nil, "Sub"])
    }

    @Test("with no root config, a config nested in another still replaces it")
    @MainActor
    func testTreeRowReplacesWithoutRoot() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig("disabled_rules:\n  - todo\n", at: "A", in: root)
        try writeConfig("disabled_rules:\n  - force_try\n", at: "A/B", in: root)
        try writeConfig("disabled_rules:\n  - force_cast\n", at: "A/B/C", in: root)

        let rows = ConfigMapPresenter().treeRows(for: tree(in: root))
        #expect(rows.map(\.displayName) == ["A", "B", "C"])
        #expect(rows.map(\.replaces) == [nil, "A", "B"])
    }

    @Test("a config the root pulls in is not replaced, skipped, or inherited from in its own right")
    @MainActor
    func testRootGraphConfigIsPartOfTheRoot() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig("child_config: Sub/.swiftlint.yml\n", at: "", in: root)
        try writeConfig("disabled_rules:\n  - force_cast\n", at: "Sub", in: root)
        try writeConfig("disabled_rules:\n  - todo\n", at: "Sub/Deeper", in: root)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Other", isDirectory: true),
            withIntermediateDirectories: true
        )

        let rows = ConfigMapPresenter().treeRows(for: tree(in: root))
        #expect(rows.map(\.displayName) == ["root", "Sub", "Deeper"])
        #expect(rows.map(\.replaces) == [nil, nil, nil])

        let atDeeper = display(at: "Sub/Deeper", in: root)
        #expect(atDeeper.layerChainLabels == ["root", "Sub", "Deeper"])
        #expect(atDeeper.skippedNotice == nil)

        // A folder with no config inherits the root's settings, Sub's among them.
        let atOther = display(at: "Other", in: root)
        #expect(atOther.layerChainLabels == ["root", "Sub"])
        #expect(atOther.inheritsNotice == "No config in this folder — it inherits from root.")
    }
}
