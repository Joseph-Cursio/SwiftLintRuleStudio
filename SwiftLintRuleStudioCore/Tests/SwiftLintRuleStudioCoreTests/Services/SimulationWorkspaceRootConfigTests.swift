//
//  SimulationWorkspaceRootConfigTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The mirror's root configuration: the file it is read from, the seed a workspace without
//  one gets, and the configs it pulls in.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct SimulationWorkspaceRootConfigTests {

    // MARK: - Helpers

    /// `<folder>/ws` holding `Sources/A.swift`, and no config yet.
    private struct Layout {
        let folder: URL

        var workspace: URL { folder.appendingPathComponent("ws", isDirectory: true) }

        func remove() {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func makeLayout() throws -> Layout {
        let layout = Layout(
            folder: FileManager.default.temporaryDirectory
                .appendingPathComponent("ShadowRootConfigTests-\(UUID().uuidString)", isDirectory: true)
        )
        try write("let a = 1\n", to: layout.workspace.appendingPathComponent("Sources/A.swift"))
        return layout
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeShadow(_ layout: Layout, baseConfigPath: URL? = nil) throws -> SimulationWorkspace {
        try SimulationWorkspaceBuilder()
            .makeWorkspace(for: Workspace(path: layout.workspace), baseConfigPath: baseConfigPath)
    }

    // MARK: - Tests

    @Test("the root config is the workspace's own when it has one, and otherwise the first seed that exists")
    func rootConfigFile() throws {
        let layout = try makeLayout()
        defer { layout.remove() }
        let base = layout.folder.appendingPathComponent("base.yml")
        try write("disabled_rules:\n  - todo\n", to: base)
        let builder = SimulationWorkspaceBuilder()
        let workspace = Workspace(path: layout.workspace)

        #expect(builder.rootConfigFile(for: workspace, baseConfigPath: base) == base)
        #expect(builder.rootConfigFile(for: workspace, baseConfigPath: nil) == nil)

        let own = layout.workspace.appendingPathComponent(".swiftlint.yml")
        try write("disabled_rules:\n  - force_cast\n", to: own)

        #expect(builder.rootConfigFile(for: workspace, baseConfigPath: base) == own)
    }

    @Test("a workspace with no config of its own gets the base config's settings at the mirror's root")
    func seededFromTheBaseConfig() throws {
        let layout = try makeLayout()
        defer { layout.remove() }
        // Not named .swiftlint.yml, so no lookup finds it beside the workspace.
        let base = layout.folder.appendingPathComponent("base.yml")
        try write("disabled_rules:\n  - todo\n", to: base)

        let shadow = try makeShadow(layout, baseConfigPath: base)
        defer { shadow.cleanup() }

        #expect(shadow.configs.map(\.relativePath) == [".swiftlint.yml"])
        #expect(shadow.configs.first?.original.disabledRules == ["todo"])
    }

    @Test("the mirror has one root config: the workspace's own, or a seed beside its nested configs")
    func oneRootConfig() throws {
        let owned = try makeLayout()
        defer { owned.remove() }
        try write("disabled_rules:\n  - todo\n", to: owned.workspace.appendingPathComponent(".swiftlint.yml"))
        let nestedOnly = try makeLayout()
        defer { nestedOnly.remove() }
        try write("line_length: 60\n", to: nestedOnly.workspace.appendingPathComponent("Sources/.swiftlint.yml"))

        let ownedShadow = try makeShadow(owned)
        defer { ownedShadow.cleanup() }
        let nestedShadow = try makeShadow(nestedOnly)
        defer { nestedShadow.cleanup() }

        #expect(ownedShadow.configs.map(\.relativePath) == [".swiftlint.yml"])
        #expect(nestedShadow.configs.map(\.relativePath) == [".swiftlint.yml", "Sources/.swiftlint.yml"])
    }

    @Test("a config the root pulls in has its excluded paths written from its own folder")
    func pulledInConfigExclusions() throws {
        let layout = try makeLayout()
        defer { layout.remove() }
        try write("child_config: Shared/child.yml\n", to: layout.workspace.appendingPathComponent(".swiftlint.yml"))
        let generated = layout.workspace.appendingPathComponent("Sources/Gen", isDirectory: true)
        try write("let g = 1\n", to: generated.appendingPathComponent("G.swift"))
        try write(
            "excluded:\n  - \(generated.path)\n",
            to: layout.workspace.appendingPathComponent("Shared/child.yml")
        )

        let shadow = try makeShadow(layout)
        defer { shadow.cleanup() }

        let child = try #require(shadow.configs.first { $0.relativePath == "Shared/child.yml" })
        #expect(child.isRootConfiguration)
        // SwiftLint reads a pulled-in config's paths from its own folder, so the copy's is too.
        #expect(child.original.excluded == ["../Sources/Gen"])
    }
}
