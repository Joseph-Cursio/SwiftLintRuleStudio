//
//  SimulationWorkspacePrivateLoopTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Under /private SwiftLint skips no symlink `excluded` names, but an excluded folder on the
//  way to one still keeps it out. These pin when a loop under /private fails the simulation,
//  and what its reason says to do, against what `swiftlint lint` does in /tmp.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct SimulationWorkspacePrivateLoopTests {

    // MARK: - Helpers

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

    /// A temp folder holding a workspace and, beside it, a folder outside it.
    private struct Layout {
        /// Clean this up.
        let base: URL
        /// Holds `.swiftlint.yml` and `Sources/A.swift`.
        let workspace: URL
    }

    /// A workspace at `<base>/ws` with `config`, and `<base>/kit` beside it holding `B.swift`.
    private func makeLayout(config: String) throws -> Layout {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowSymlinkTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let layout = Layout(base: base, workspace: base.appendingPathComponent("ws", isDirectory: true))
        try write(config, to: layout.workspace.appendingPathComponent(".swiftlint.yml"))
        try write("let a = 1\n", to: layout.workspace.appendingPathComponent("Sources/A.swift"))
        try write("let b = 1\n", to: base.appendingPathComponent("kit/B.swift"))
        return layout
    }

    /// The mirror plan for `layout`'s workspace, under /private as a test's temp folder is.
    private func planUnderPrivate(_ layout: Layout) throws -> WorkspaceMirrorPlan {
        let scope = try MirrorScope.make(
            workspaceRoot: layout.workspace,
            rootConfig: layout.workspace.appendingPathComponent(".swiftlint.yml")
        )
        try #require(scope.isUnderPrivate, "the temporary directory isn't under /private")
        return try WorkspaceMirrorPlan.make(for: scope)
    }

    // MARK: - Tests

    @Test("under /private SwiftLint follows an excluded loop all the same, so the simulation fails")
    func excludedCyclicLinkUnderPrivateFails() throws {
        // There it matches a link's path with /private dropped against patterns that keep it.
        let layout = try makeLayout(config: "excluded:\n  - Sources/loop\n")
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try link(layout.workspace.appendingPathComponent("Sources/loop"), to: "..")

        let error = #expect(throws: MirrorUnsupportedSetupError.self) {
            try SimulationWorkspaceBuilder().makeWorkspace(for: Workspace(path: layout.workspace), baseConfigPath: nil)
        }
        // Excluding the folder that holds it does keep SwiftLint out; see below.
        #expect(error?.reason.contains("exclude Sources, the folder that holds it, or remove the link") == true)
        #expect(error?.reason.contains("Add it to `excluded`") == false)
    }

    /// Under /private SwiftLint matches each entry of a folder it lists by its real path, which
    /// keeps the prefix as the patterns do: an excluded folder on the way keeps it from a loop.
    /// What `swiftlint lint` 0.65.1 does with each layout in /tmp: no crash.
    @Test(
        "under /private an excluded folder on the way to a loop keeps SwiftLint out, so it is left out",
        arguments: [
            ("excluded:\n  - Sources\n", "Sources/loop", ".."),
            ("excluded:\n  - \"Sour*\"\n", "Sources/loop", ".."),
            ("excluded:\n  - Sources/Deep\n", "Sources/Deep/loop", "../.."),
            ("included:\n  - Sources\nexcluded:\n  - Sources/Gen\n", "Sources/Gen/loop", "../.."),
            // Inside a link's target too: the listing gives the real path, with the prefix.
            ("excluded:\n  - ../kit/Vendor\n", "../kit/Vendor/loop", "..")
        ]
    )
    func loopBehindExcludedFolderUnderPrivateIsLeftOut(config: String, loop: String, to destination: String) throws {
        let layout = try makeLayout(config: config)
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try link(layout.workspace.appendingPathComponent("Libs"), to: "../kit")
        try link(layout.workspace.appendingPathComponent(loop), to: destination)

        let plan = try planUnderPrivate(layout)

        #expect(!plan.links.contains { $0.path.hasSuffix("/loop") }, "\(config)")
    }

    /// The exclusions that don't keep SwiftLint out under /private: on the link itself, on the
    /// folder a link leads into — matched, like the link, with the prefix dropped — and on the
    /// folder a walk starts from, which SwiftLint never matches. `swiftlint lint` 0.65.1 crashes
    /// on the first two in /tmp; on the last it gets through the loop once, linting what the
    /// mirror, leaving the link out, wouldn't.
    @Test(
        "under /private a loop no folder on the way keeps SwiftLint out of fails the simulation",
        arguments: [
            ("excluded:\n  - loop\n", "loop", ".", "remove the link, or keep it in a folder `excluded` names"),
            ("excluded:\n  - Abc\n", "Abc/loop", "..", "remove the link"),
            ("excluded:\n  - Shared\n", "Shared/loop", "..", "remove the link"),
            ("included:\n  - Sources\nexcluded:\n  - Sources\n", "Sources/loop", "..", "remove the link")
        ]
    )
    func loopNoExclusionKeepsOutUnderPrivateFails(
        config: String,
        loop: String,
        to destination: String,
        advice: String
    ) throws {
        let layout = try makeLayout(config: config)
        defer { try? FileManager.default.removeItem(at: layout.base) }
        let folder = loop.split(separator: "/").dropLast().joined(separator: "/")
        try link(layout.workspace.appendingPathComponent(loop), to: destination)
        if !folder.isEmpty, folder != "Sources" {
            // A link to the excluded folder: SwiftLint walks into it through that, from either
            // side of the folder in the listing.
            try link(layout.workspace.appendingPathComponent(folder == "Abc" ? "Zlnk" : "Libs"), to: folder)
        }

        let error = #expect(throws: MirrorUnsupportedSetupError.self, "\(config)") {
            _ = try planUnderPrivate(layout)
        }
        #expect(error?.reason.contains(advice) == true, "\(error?.reason ?? "")")
        #expect(error?.reason.contains("Add it to `excluded`") == false)
    }
}
