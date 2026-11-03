//
//  WorkspaceMirrorPlanTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  What the plan puts in a mirror, read off the plan itself: the configs above the folders it
//  copies, whether lookups can climb out of the container, and the links it keeps or leaves out.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct WorkspaceMirrorPlanTests {

    // MARK: - Helpers

    private func makeTempFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceMirrorPlanTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func link(_ url: URL, to destination: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }

    private func resolved(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    private func scope(of workspace: URL) throws -> MirrorScope {
        try MirrorScope.make(workspaceRoot: workspace, rootConfig: workspace.appendingPathComponent(".swiftlint.yml"))
    }

    /// A temp folder holding a workspace and, beside it, a folder outside it.
    private struct Layout {
        /// Clean this up.
        let base: URL
        /// Holds `.swiftlint.yml` and `Sources/A.swift`.
        let workspace: URL
        /// Beside the workspace; holds `B.swift`.
        let kit: URL
    }

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

    /// Fails the test unless no config sits above `folder`, which the climbing tests rely on.
    private func requireNoConfigAbove(_ folder: URL) throws {
        try #require(
            WorkspaceMirrorPlan.nearestConfig(from: folder, fileManager: .default) == nil,
            "a .swiftlint.yml above the temp folder"
        )
    }

    // MARK: - The workspace

    @Test("the plan's workspace root is the workspace's real path")
    func workspaceRoot() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        let scope = try scope(of: layout.workspace)

        #expect(try WorkspaceMirrorPlan.make(for: scope).workspaceRoot == scope.workspaceRoot)
    }

    @Test("the workspace's own entries don't count toward the limit on what the mirror copies from outside")
    func workspaceEntriesAreNotCounted() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try write("let b = 1\n", to: layout.workspace.appendingPathComponent("Sources/B.swift"))
        let scope = try scope(of: layout.workspace)

        #expect(throws: Never.self) { try WorkspaceMirrorPlan.make(for: scope, outsideEntryLimit: 1) }
    }

    // MARK: - Links

    @Test("a file link counts by its name or its target's; one to a file the mirror lacks is copied in its place")
    func fileLinksByNameOrTarget() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try write("notes\n", to: layout.workspace.appendingPathComponent("notes.txt"))
        try link(layout.workspace.appendingPathComponent("Notes.swift"), to: "notes.txt")
        try link(layout.workspace.appendingPathComponent("Script"), to: "Sources/A.swift")

        let plan = try WorkspaceMirrorPlan.make(for: scope(of: layout.workspace))

        #expect(plan.sources.contains { $0.path == "ws/Notes.swift" && $0.source.lastPathComponent == "notes.txt" })
        #expect(!plan.links.contains { $0.path == "ws/Notes.swift" })
        #expect(plan.links.contains { $0.path == "ws/Script" })
    }

    @Test("a link back into a folder that holds it is left out, even where the walk never reaches it")
    func unwalkedLoopIsLeftOut() throws {
        // Nothing excluded: the walk follows no link, so it never meets this one.
        let layout = try makeLayout(config: "disabled_rules:\n  - todo\n")
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try link(layout.workspace.appendingPathComponent("Sources/loop"), to: "..")

        let plan = try WorkspaceMirrorPlan.make(for: scope(of: layout.workspace))

        #expect(plan.sources.contains { $0.path == "ws/Sources/A.swift" })
        #expect(!plan.links.contains { $0.path == "ws/Sources/loop" })
    }

    @Test("a link back into the workspace, off the way to an included file, is left out")
    func loopOffTheWayToAnIncludedFile() throws {
        let layout = try makeLayout(config: "included:\n  - Sources/A.swift\nexcluded:\n  - Nope\n")
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try link(layout.workspace.appendingPathComponent("loop"), to: ".")

        let plan = try WorkspaceMirrorPlan.make(for: scope(of: layout.workspace))

        #expect(!plan.links.contains { $0.path == "ws/loop" })
    }

    // MARK: - Configs above, and lookups out of the container

    @Test("outside /private, a link beside the workspace puts the nearest config above its folder at the container")
    func besideLinkGetsTheConfigAbove() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        let above = layout.base.appendingPathComponent(".swiftlint.yml")
        try write("disabled_rules:\n  - force_cast\n", to: above)
        try link(layout.workspace.appendingPathComponent("Shared"), to: "../kit")

        let plan = try WorkspaceMirrorPlan.make(for: scope(of: layout.workspace).underPrivate(false))

        #expect(plan.configs.contains { $0.path == ".swiftlint.yml" && resolved($0.source) == resolved(above) })
        #expect(!plan.climbsPastContainer, "the config at the container stops lookups there")
    }

    @Test("outside /private, with no config above to stop them, lookups from beside the workspace climb out")
    func besideLinkWithNothingAboveClimbs() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try requireNoConfigAbove(layout.base)
        try link(layout.workspace.appendingPathComponent("Shared"), to: "../kit")

        let plan = try WorkspaceMirrorPlan.make(for: scope(of: layout.workspace).underPrivate(false))

        #expect(plan.climbsPastContainer)
    }

    @Test("under /private, lookups from the workspace's own files climb out of the container; elsewhere they don't")
    func underPrivateClimbs() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try requireNoConfigAbove(layout.base)
        let scope = try scope(of: layout.workspace)
        try #require(scope.isUnderPrivate, "the temporary directory isn't under /private")

        #expect(try WorkspaceMirrorPlan.make(for: scope).climbsPastContainer)
        #expect(try !WorkspaceMirrorPlan.make(for: scope.underPrivate(false)).climbsPastContainer)
    }

    @Test("under /private, the configs between the workspace's folder and the container's are mirrored; elsewhere not")
    func configsBetweenUnderPrivate() throws {
        // The parent config two folders up makes the container stand for `base`, above `mid`.
        let base = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let workspace = base.appendingPathComponent("mid/ws", isDirectory: true)
        try write("parent_config: ../../parent.yml\n", to: workspace.appendingPathComponent(".swiftlint.yml"))
        try write("let a = 1\n", to: workspace.appendingPathComponent("Sources/A.swift"))
        try write("disabled_rules:\n  - todo\n", to: base.appendingPathComponent("parent.yml"))
        try write("disabled_rules:\n  - force_cast\n", to: base.appendingPathComponent("mid/.swiftlint.yml"))
        let scope = try scope(of: workspace)
        try #require(scope.isUnderPrivate, "the temporary directory isn't under /private")

        let between = { (plan: WorkspaceMirrorPlan) in plan.configs.contains { $0.path == "mid/.swiftlint.yml" } }
        #expect(try between(WorkspaceMirrorPlan.make(for: scope)))
        #expect(try !between(WorkspaceMirrorPlan.make(for: scope.underPrivate(false))))
    }

    @Test("a folder further out than the container's gets the config above it beside its copy, stopping lookups there")
    func outsideFolderConfigStopsLookups() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        let other = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: other) }
        try write("let c = 1\n", to: other.appendingPathComponent("kit/C.swift"))
        try write("disabled_rules:\n  - force_cast\n", to: other.appendingPathComponent(".swiftlint.yml"))
        try link(layout.workspace.appendingPathComponent("Shared"), to: other.appendingPathComponent("kit").path)

        let plan = try WorkspaceMirrorPlan.make(for: scope(of: layout.workspace).underPrivate(false))

        #expect(plan.configs.contains { $0.path == MirrorScope.outsideFolderName + "/0/.swiftlint.yml" })
        #expect(!plan.climbsPastContainer)
    }

    @Test("a file linked from further out than the container's folder gets the config nearest its real folder")
    func outsideFileGetsItsConfig() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        let other = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: other) }
        let config = other.appendingPathComponent("kit/.swiftlint.yml")
        try write("let c = 1\n", to: other.appendingPathComponent("kit/C.swift"))
        try write("disabled_rules:\n  - force_cast\n", to: config)
        try link(
            layout.workspace.appendingPathComponent("Sources/E.swift"),
            to: other.appendingPathComponent("kit/C.swift").path
        )

        let plan = try WorkspaceMirrorPlan.make(for: scope(of: layout.workspace))

        #expect(plan.configs.contains { resolved($0.source) == resolved(config) })
    }
}
