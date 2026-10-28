//
//  MirrorExclusionRewriteTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The mirror writes each `excluded` entry to name in the container what it names in the
//  workspace, takes the entries SwiftLint merges away out of its reckoning, and refuses the
//  entries it can't place.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct MirrorExclusionRewriteTests {

    /// An entry from a config read relative to `base`, whose copy is at `mirrorBase`, in a
    /// container standing for `/a`; `/opt/kit` is copied in its outside folder.
    nonisolated struct Rewrite: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let entry: String
        var base = "/a/ws"
        var mirrorBase = "ws"
        let written: String
    }

    nonisolated static let rewrites: [Rewrite] = [
        Rewrite(testDescription: "relative, below the anchor", entry: "Gen", written: "Gen"),
        Rewrite(testDescription: "climbing, but not past the anchor", entry: "../kit/G", written: "../kit/G"),
        Rewrite(testDescription: "absolute", entry: "/a/ws/Gen", written: "Gen"),
        Rewrite(testDescription: "absolute, beside the workspace", entry: "/a/kit/G", written: "../kit/G"),
        Rewrite(testDescription: "absolute glob", entry: "/a/ws/G*", written: "G*"),
        Rewrite(testDescription: "absolute, the workspace itself", entry: "/a/ws", written: "."),
        Rewrite(testDescription: "climbing past the anchor and back", entry: "../../a/ws/Gen", written: "Gen"),
        Rewrite(
            testDescription: "from a parent config at the anchor",
            entry: "/a/ws/Gen",
            base: "/a",
            mirrorBase: "",
            written: "ws/Gen"
        ),
        Rewrite(
            testDescription: "into a folder copied in the outside folder",
            entry: "/opt/kit/G",
            written: "../.swiftlint-rule-studio-outside/0/tree/G"
        ),
        Rewrite(testDescription: "naming nothing the mirror holds", entry: "/opt/other/G", written: "/opt/other/G"),
        Rewrite(testDescription: "from the folder SwiftLint runs in", entry: "${PWD}/Gen", written: "${PWD}/Gen")
    ]

    /// `/opt/kit`, copied in the mirror's outside folder.
    nonisolated static let outside = [
        WorkspaceMirrorPlan.ExternalFolder(
            original: URL(fileURLWithPath: "/opt/kit"),
            path: ".swiftlint-rule-studio-outside/0/tree"
        )
    ]

    @Test("an `excluded` entry is written to name in the container what it names in the workspace", arguments: rewrites)
    func rewrite(_ rewrite: Rewrite) throws {
        let written = try MirrorPaths.mirroredExclusion(
            rewrite.entry,
            base: rewrite.base,
            mirrorBase: rewrite.mirrorBase,
            anchor: "/a",
            outsideFolders: Self.outside
        )
        #expect(written == rewrite.written)
    }

    @Test("under /tmp, /var and /etc a /private spelling is placed as the mirror spells it; elsewhere not")
    func privateSpelling() throws {
        let written = try MirrorPaths.mirroredExclusion(
            "/private/tmp/a/ws/Gen", base: "/tmp/a/ws", mirrorBase: "ws", anchor: "/tmp/a", outsideFolders: []
        )
        #expect(written == "Gen")
        #expect(MirrorPaths.unprivate("/private/Users/me/ws") == "/private/Users/me/ws")
    }

    @Test("`~/` is the home folder; a bare `~` SwiftLint takes as a name")
    func home() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(MirrorPaths.absolute("~/dev/ws/Gen", base: "/x") == home + "/dev/ws/Gen")
        #expect(MirrorPaths.absolute("~", base: "/x") == "/x/~")
    }

    @Test("an entry starting above an outside folder the mirror copies is refused")
    func aboveAnOutsideFolder() {
        #expect(throws: MirrorUnsupportedSetupError.self) {
            try MirrorPaths.mirroredExclusion(
                "/opt/*/G", base: "/a/ws", mirrorBase: "ws", anchor: "/a", outsideFolders: Self.outside
            )
        }
    }

    // MARK: - The scope

    private func makeWorkspace(_ config: String, in folder: String = "ws") throws -> (base: URL, workspace: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MirrorExclusionRewriteTests-\(UUID().uuidString)", isDirectory: true)
        let workspace = base.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try config.write(to: workspace.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        return (base, workspace)
    }

    private func scope(of workspace: URL) throws -> MirrorScope {
        try MirrorScope.make(workspaceRoot: workspace, rootConfig: workspace.appendingPathComponent(".swiftlint.yml"))
    }

    @Test("a parent's exclusion of a folder its child includes keeps nothing out, as SwiftLint merges them")
    func mergedAway() throws {
        let (base, workspace) = try makeWorkspace(
            "parent_config: ../parent.yml\nincluded:\n  - Sources\n  - Packages/Kit\nexcluded:\n  - Nope\n"
        )
        defer { try? FileManager.default.removeItem(at: base) }
        try "excluded:\n  - ws/Packages/Kit\n".write(
            to: base.appendingPathComponent("parent.yml"), atomically: true, encoding: .utf8
        )

        let merged = try scope(of: workspace)
        #expect(!merged.exclusions.excludes(merged.workspaceRoot + "/Packages/Kit/loop"))
        #expect(merged.exclusions.excludes(merged.workspaceRoot + "/Nope"))
        #expect(merged.reach == .everyLink)

        // With nothing else excluded, SwiftLint lists files as it does with no exclusions.
        try "parent_config: ../parent.yml\nincluded:\n  - Sources\n  - Packages/Kit\n".write(
            to: workspace.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8
        )
        #expect(try scope(of: workspace).reach == .towardIncluded([["Sources"], ["Packages", "Kit"]]))
    }

    @Test("a child config's exclusion of a folder its parent includes drops that entry")
    func childExcludesParentsEntry() throws {
        let (base, workspace) = try makeWorkspace(
            "child_config: child.yml\nincluded:\n  - Sources\n  - Generated\n"
        )
        defer { try? FileManager.default.removeItem(at: base) }
        try "excluded:\n  - Generated\n".write(
            to: workspace.appendingPathComponent("child.yml"), atomically: true, encoding: .utf8
        )

        #expect(try scope(of: workspace).walkRoots == [["Sources"]])
    }

    @Test("an exclusion starting above the folder the container stands for is refused")
    func startsAboveTheAnchor() throws {
        let (base, workspace) = try makeWorkspace("excluded:\n  - ../../*/Gen\n")
        defer { try? FileManager.default.removeItem(at: base) }

        let error = #expect(throws: MirrorUnsupportedSetupError.self) { try scope(of: workspace) }
        #expect(error?.reason.contains("starts above") == true)
    }

    @Test("a workspace in a folder whose path holds `[` is refused when the configuration names paths")
    func bracketsAboveTheWorkspace() throws {
        let (base, workspace) = try makeWorkspace("excluded:\n  - Gen\n", in: "proj[1]/ws")
        defer { try? FileManager.default.removeItem(at: base) }

        let error = #expect(throws: MirrorUnsupportedSetupError.self) { try scope(of: workspace) }
        #expect(error?.reason.contains("holds a `[`") == true)

        try "disabled_rules:\n  - todo\n".write(
            to: workspace.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8
        )
        #expect(throws: Never.self) { try scope(of: workspace) }
    }

    // MARK: - The mirror

    @Test("the mirror's root config names the folder an absolute exclusion names, relative to the lint root")
    func mirrorConfigIsRewritten() throws {
        let (base, workspace) = try makeWorkspace("")
        defer { try? FileManager.default.removeItem(at: base) }
        try "excluded:\n  - \(workspace.resolvingSymlinksInPath().path)/Gen\n".write(
            to: workspace.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: workspace.appendingPathComponent("Gen"), withIntermediateDirectories: true
        )
        try "let g = 1\n".write(to: workspace.appendingPathComponent("Gen/G.swift"), atomically: true, encoding: .utf8)

        let shadow = try SimulationWorkspaceBuilder()
            .makeWorkspace(for: Workspace(path: workspace), baseConfigPath: nil)
        defer { shadow.cleanup() }
        try shadow.applyRule("force_cast", isOptIn: false, isAnalyzer: false, parameterOverrides: nil)

        let config = try YAMLConfigurationEngine.loadConfig(at: shadow.root.appendingPathComponent(".swiftlint.yml"))
        #expect(config.excluded == ["Gen"])
    }
}
