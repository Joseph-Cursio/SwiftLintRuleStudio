//
//  ConfigMapPresenterTests+ReferencedConfigs.swift
//  SwiftLintRuleStudioCoreTests
//
//  The Config Map's account of the configs the root pulls in from beyond the workspace's own
//  `.swiftlint.yml` files. They have no folder in the workspace to be a row for, so the root's
//  row names them, and the inspector says when one can't be read.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

extension ConfigMapPresenterTests {
    /// A package opened on its own at `Packages/Foo`, pulling in its repository's config and a
    /// remote config SwiftLint hasn't fetched yet.
    private func makePackageWorkspace() throws -> (repository: URL, workspace: URL) {
        let repository = try makeWorkspace()
        try writeConfig("disabled_rules:\n  - todo\nexcluded:\n  - Pods\n", at: "", in: repository)
        try writeConfig(
            "parent_config: ../../.swiftlint.yml\nchild_config: https://example.com/strict.yml\n"
                + "excluded:\n  - Generated\n",
            at: "Packages/Foo",
            in: repository
        )
        try writeConfig("disabled_rules:\n  - force_cast\n", at: "Packages/Foo/Sub", in: repository)
        return (repository, repository.appendingPathComponent("Packages/Foo", isDirectory: true))
    }

    @Test("the root's row names the configs it pulls in from beyond the workspace; no other row does")
    @MainActor
    func testRootRowNamesPulledInConfigs() throws {
        let (repository, workspace) = try makePackageWorkspace()
        defer { cleanup(repository) }

        let rows = ConfigMapPresenter().treeRows(for: tree(in: workspace))
        #expect(rows.map(\.displayName) == ["root", "Sub"])
        #expect(rows.first?.pullsIn == ["../../.swiftlint.yml", "https://example.com/strict.yml"])
        #expect(rows.last?.pullsIn.isEmpty == true)
    }

    @Test("the inspector attributes settings to a config outside the workspace and names one it can't read")
    @MainActor
    func testInspectorForPulledInConfigs() throws {
        let (repository, workspace) = try makePackageWorkspace()
        defer { cleanup(repository) }
        let configTree = tree(in: workspace)
        let resolved = ResolvedConfigurationEngine().resolve(
            at: workspace.appendingPathComponent("Sub", isDirectory: true),
            in: configTree
        )
        let display = ConfigMapPresenter().display(for: resolved, in: configTree)

        #expect(display.layerChainLabels == [
            "../../.swiftlint.yml",
            "root",
            "https://example.com/strict.yml",
            "Sub"
        ])
        let todo = try #require(display.ruleRows.first { $0.id == "todo" })
        #expect(todo.setBy == "../../.swiftlint.yml")
        #expect(display.excludedNotice == "excluded: ../../Pods (../../.swiftlint.yml); Generated (root)")
        #expect(
            display.unreadNotice
                == "https://example.com/strict.yml isn't shown: SwiftLint fetches it the next time it lints here."
        )
        #expect(display.skippedNotice == nil)
    }

    @Test("with nothing pulled in from beyond the workspace, nothing is named")
    @MainActor
    func testNoPulledInConfigs() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig("excluded:\n  - Generated\n", at: "", in: root)
        let configTree = tree(in: root)
        let display = ConfigMapPresenter().display(
            for: ResolvedConfigurationEngine().resolve(at: root, in: configTree),
            in: configTree
        )

        #expect(ConfigMapPresenter().treeRows(for: configTree).first?.pullsIn.isEmpty == true)
        #expect(display.unreadNotice == nil)
        #expect(display.excludedNotice == "excluded (root): Generated")
    }
}
