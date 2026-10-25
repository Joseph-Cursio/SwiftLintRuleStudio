//
//  SimulationWorkspaceLinkReachTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The mirror walks only the links SwiftLint can follow, never `/`, and fills a link's target
//  even under a folder it otherwise prunes.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct SimulationWorkspaceLinkReachTests {

    // MARK: - Helpers

    private func makeTempFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowSymlinkTests", isDirectory: true)
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

    private func link(_ url: URL, to destination: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }

    private func loadConfig(at url: URL) throws -> YAMLConfigurationEngine.YAMLConfig {
        let engine = YAMLConfigurationEngine(configPath: url)
        try engine.load()
        return engine.getConfig()
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func resolved(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    /// A temp folder holding a workspace and, beside it, a folder outside it.
    private struct Layout {
        /// Clean this up.
        let base: URL
        /// Holds `.swiftlint.yml` and `Sources/A.swift`.
        let workspace: URL
        /// Outside the workspace; holds `B.swift`.
        let kit: URL
    }

    /// With `excluded` set, as most configs have, SwiftLint follows every link it meets.
    private func makeLayout(config: String = "excluded:\n  - Nope\n") throws -> Layout {
        let base = try makeTempFolder()
        let layout = Layout(
            base: base,
            workspace: base.appendingPathComponent("ws", isDirectory: true),
            kit: base.appendingPathComponent("kit", isDirectory: true)
        )
        try write(config, to: layout.workspace.appendingPathComponent(".swiftlint.yml"))
        try write("let a = 1\n", to: layout.workspace.appendingPathComponent("Sources/A.swift"))
        try write("let b = 1\n", to: layout.kit.appendingPathComponent("B.swift"))
        return layout
    }

    private func scope(of layout: Layout) throws -> MirrorScope {
        try MirrorScope.make(
            workspaceRoot: layout.workspace,
            rootConfig: layout.workspace.appendingPathComponent(".swiftlint.yml")
        )
    }

    private func makeShadow(for workspace: URL, applying ruleId: String = "force_cast") throws -> SimulationWorkspace {
        let shadow = try SimulationWorkspaceBuilder().makeWorkspace(
            for: Workspace(path: workspace),
            baseConfigPath: nil
        )
        try shadow.applyRule(ruleId, isOptIn: false, isAnalyzer: false, parameterOverrides: nil)
        return shadow
    }

    @Test("a link SwiftLint can't follow is left out, and the folder behind it isn't walked")
    func unfollowableLinkIsLeftOut() throws {
        // With no `excluded`, `subpaths` goes into no link; one off the way to every `included`
        // entry is never linted, and walking a big folder behind it would be wasted.
        for config in ["disabled_rules:\n  - todo\n", "included:\n  - Sources\n"] {
            let layout = try makeLayout(config: config)
            defer { try? FileManager.default.removeItem(at: layout.base) }
            try link(layout.workspace.appendingPathComponent("Sources/Shared"), to: "../../kit")

            let plan = try WorkspaceMirrorPlan.make(for: scope(of: layout))

            #expect(plan.externalFolders.isEmpty, "\(config)")
            #expect(!plan.links.contains { $0.path == "ws/Sources/Shared" }, "\(config)")
        }
    }

    @Test("an included entry that is a link is followed when the config excludes nothing")
    func includedLinkIsFollowedWithoutExclusions() throws {
        let layout = try makeLayout(config: "included:\n  - Shared\n")
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try link(layout.workspace.appendingPathComponent("Shared"), to: "../kit")

        let shadow = try makeShadow(for: layout.workspace)
        defer { shadow.cleanup() }

        #expect(isSymlink(shadow.root.appendingPathComponent("Shared")))
        #expect(FileManager.default.fileExists(atPath: shadow.root.appendingPathComponent("Shared/B.swift").path))
    }

    @Test("a link to / is a cycle, not the whole disk")
    func linkToTheRootIsACycle() throws {
        // SwiftLint follows it back into the workspace for ever; excluded, it skips it — outside
        // /private, where it matches a link's path as the pattern spells it.
        let layout = try makeLayout(config: "excluded:\n  - Sources/everything\n")
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try link(layout.workspace.appendingPathComponent("Sources/everything"), to: "/")

        let plan = try WorkspaceMirrorPlan.make(for: scope(of: layout).underPrivate(false))

        #expect(plan.externalFolders.isEmpty)
        #expect(!plan.links.contains { $0.path == "ws/Sources/everything" })
    }

    @Test("a link to / that SwiftLint follows fails the simulation")
    func followedLinkToTheRootFails() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try link(layout.workspace.appendingPathComponent("Sources/everything"), to: "/")

        #expect(throws: MirrorUnsupportedSetupError.self) {
            try WorkspaceMirrorPlan.make(for: scope(of: layout))
        }
    }

    @Test("folders like .build are mirrored, and a link into one is filled")
    func defaultExcludedFolderNamesAreMirrored() throws {
        // SwiftLint lints `.build`, `Pods` and the like unless the config excludes them, and
        // `Generated -> .build/plugins/outputs/gen` through the link.
        let layout = try makeLayout(config: "included:\n  - Sources\n  - Generated\n")
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try write("let g = 1\n", to: layout.workspace.appendingPathComponent(".build/plugins/outputs/gen/G.swift"))
        try write("let o = 1\n", to: layout.workspace.appendingPathComponent(".build/Other.swift"))
        try link(layout.workspace.appendingPathComponent("Generated"), to: ".build/plugins/outputs/gen")

        let shadow = try makeShadow(for: layout.workspace)
        defer { shadow.cleanup() }

        #expect(FileManager.default.fileExists(atPath: shadow.root.appendingPathComponent("Generated/G.swift").path))
        #expect(FileManager.default.fileExists(atPath: shadow.root.appendingPathComponent(".build/Other.swift").path))
    }
}
