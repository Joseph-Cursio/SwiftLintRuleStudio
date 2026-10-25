//
//  MirrorScopeTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  What the mirror must reach beyond the workspace, from the configs that decide it — and the
//  setups it refuses rather than measure short.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct MirrorScopeTests {

    // MARK: - Helpers

    /// `<base>/ws` holding `.swiftlint.yml` and `Sources/A.swift`. Clean up `base`.
    private struct Layout {
        let base: URL
        let workspace: URL
    }

    private func makeLayout(config: String) throws -> Layout {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MirrorScopeTests-\(UUID().uuidString)", isDirectory: true)
        let layout = Layout(base: base, workspace: base.appendingPathComponent("ws", isDirectory: true))
        try write(config, to: layout.workspace.appendingPathComponent(".swiftlint.yml"))
        try write("let a = 1\n", to: layout.workspace.appendingPathComponent("Sources/A.swift"))
        return layout
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func scope(of layout: Layout) throws -> MirrorScope {
        try MirrorScope.make(
            workspaceRoot: layout.workspace,
            rootConfig: layout.workspace.appendingPathComponent(".swiftlint.yml")
        )
    }

    private func resolved(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    // MARK: - included

    @Test("an entry beside the workspace is hosted, and entries that climb back in read as inside")
    func entriesAreStandardized() throws {
        let layout = try makeLayout(config: "included:\n  - ../Shared\n  - Sources/../Lib\n  - ../WS/Tests\n")
        defer { try? FileManager.default.removeItem(at: layout.base) }

        let scope = try scope(of: layout)

        #expect(scope.hostedFolders == [resolved(layout.base) + "/Shared"])
        #expect(scope.reach == .towardIncluded([["..", "Shared"], ["Lib"], ["Tests"]]))
    }

    @Test("an absolute or home-relative entry, or a pattern over a folder holding the workspace, is refused")
    func unplaceableEntriesAreRefused() throws {
        for entry in ["/Library/Code", "~/Code", "../*", ".."] {
            let layout = try makeLayout(config: "included:\n  - \"\(entry)\"\n")
            defer { try? FileManager.default.removeItem(at: layout.base) }

            #expect(throws: MirrorUnsupportedSetupError.self, "\(entry)") {
                try scope(of: layout)
            }
        }
    }

    @Test("an entry more than eight folders above the workspace is refused; eight is placed")
    func climbIsBounded() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MirrorScopeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let workspace = (1...9).reduce(base) { $0.appendingPathComponent("\($1)") }.appendingPathComponent("ws")
        try write("let a = 1\n", to: workspace.appendingPathComponent("Sources/A.swift"))

        for (levels, refused) in [(8, false), (9, true)] {
            let entry = String(repeating: "../", count: levels) + "X"
            try write("included:\n  - \(entry)\n", to: workspace.appendingPathComponent(".swiftlint.yml"))
            let config = workspace.appendingPathComponent(".swiftlint.yml")
            let make = { try MirrorScope.make(workspaceRoot: workspace, rootConfig: config) }
            if refused {
                #expect(throws: MirrorUnsupportedSetupError.self) { try make() }
            } else {
                #expect(try make().lintRoot.split(separator: "/").count == 8)
            }
        }
    }

    @Test("excluded and included in their single-string form read as lists of one")
    func scalarLists() throws {
        let layout = try makeLayout(config: "excluded: Pods\nincluded: Sources\n")
        defer { try? FileManager.default.removeItem(at: layout.base) }

        let scope = try scope(of: layout)

        #expect(scope.reach == .everyLink)
        #expect(scope.walkRoots == [["Sources"]])
        #expect(scope.exclusions.excludes(resolved(layout.workspace) + "/Pods/P.swift"))
    }

    @Test("SwiftLint walks from folder entries only: not a .swift pattern, not an entry that is a link")
    func walkRoots() throws {
        let layout = try makeLayout(
            config: "excluded:\n  - Nope\nincluded:\n  - Sources\n  - Sources/**/*.swift\n  - Linked\n"
        )
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try FileManager.default.createSymbolicLink(
            atPath: layout.workspace.appendingPathComponent("Linked").path,
            withDestinationPath: "Sources"
        )

        #expect(try scope(of: layout).walkRoots == [["Sources"]])

        try write("excluded:\n  - Nope\n", to: layout.workspace.appendingPathComponent(".swiftlint.yml"))
        #expect(try scope(of: layout).walkRoots == nil, "with no included, the whole workspace")
    }

    // MARK: - Referenced configs

    @Test("parent and child configs in or beside the workspace are placed where SwiftLint looks for them")
    func referencedConfigsArePlaced() throws {
        let layout = try makeLayout(config: "parent_config: ../base.yml\nchild_config: child.yml\n")
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try write("parent_config: base2.yml\nexcluded:\n  - Gen\n", to: layout.base.appendingPathComponent("base.yml"))
        try write("line_length: 100\n", to: layout.base.appendingPathComponent("base2.yml"))
        try write("line_length: 90\n", to: layout.workspace.appendingPathComponent("child.yml"))

        let scope = try scope(of: layout)

        #expect(scope.referencedConfigs.map(\.path) == ["base.yml", "base2.yml", "ws/child.yml"])
        #expect(scope.configGraph.contains(resolved(layout.base.appendingPathComponent("base2.yml"))))
        // A parent's `excluded` is relative to its own folder.
        #expect(scope.exclusions.excludes(resolved(layout.base) + "/Gen"))
        #expect(scope.reach == .everyLink)
    }

    @Test("an absolute or a remote parent config is refused")
    func absoluteAndRemoteParents() throws {
        // A remote one can turn the rule off, and the mirror can't rewrite it.
        for parent in ["/Library/base.yml", "https://example.com/base.yml"] {
            let layout = try makeLayout(config: "parent_config: \(parent)\n")
            defer { try? FileManager.default.removeItem(at: layout.base) }
            #expect(throws: MirrorUnsupportedSetupError.self, "\(parent)") {
                try scope(of: layout)
            }
        }
    }

    @Test("a package opened alone, pulling in its repository's config, is mirrored with the lint root deeper")
    func monorepoPackage() throws {
        // `<base>/ws` stands for `mono/Packages/Core`: the container stands for `<base>`'s parent.
        let layout = try makeLayout(config: "parent_config: ../../.swiftlint.yml\nincluded:\n  - Sources\n  - ../Lib\n")
        defer { try? FileManager.default.removeItem(at: layout.base) }
        let mono = layout.base.deletingLastPathComponent()
        let repoConfig = mono.appendingPathComponent(".swiftlint.yml")
        try write("line_length: 100\n", to: repoConfig)
        defer { try? FileManager.default.removeItem(at: repoConfig) }

        let scope = try scope(of: layout)

        #expect(scope.anchor == resolved(mono))
        #expect(scope.lintRoot == layout.base.lastPathComponent + "/ws")
        #expect(scope.referencedConfigs.map(\.path) == [".swiftlint.yml"])
        #expect(scope.hostedFolders == [resolved(layout.base) + "/Lib"])
        #expect(scope.reach == .towardIncluded([["Sources"], ["..", "Lib"]]))
    }

    // MARK: - Where the workspace is

    @Test("a workspace that is itself a symlink is refused")
    func symlinkedWorkspaceIsRefused() throws {
        let layout = try makeLayout(config: "excluded:\n  - Nope\n")
        defer { try? FileManager.default.removeItem(at: layout.base) }
        let opened = layout.base.appendingPathComponent("Opened")
        try FileManager.default.createSymbolicLink(atPath: opened.path, withDestinationPath: "ws")

        // Linting a link, SwiftLint with `excluded` set finds nothing at all.
        #expect(throws: MirrorUnsupportedSetupError.self) {
            try MirrorScope.make(workspaceRoot: opened, rootConfig: opened.appendingPathComponent(".swiftlint.yml"))
        }
    }

    @Test("under /private, a workspace open through a linked folder is refused")
    func linkedFolderUnderPrivateIsRefused() throws {
        let layout = try makeLayout(config: "disabled_rules:\n  - todo\n")
        defer { try? FileManager.default.removeItem(at: layout.base) }
        let via = layout.base.deletingLastPathComponent().appendingPathComponent("via-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(atPath: via.path, withDestinationPath: layout.base.path)
        defer { try? FileManager.default.removeItem(at: via) }
        let opened = via.appendingPathComponent("ws")

        #expect(MirrorScope.isUnderPrivate(opened))
        #expect(throws: MirrorUnsupportedSetupError.self) {
            try MirrorScope.make(workspaceRoot: opened, rootConfig: opened.appendingPathComponent(".swiftlint.yml"))
        }
    }

    @Test("the temp folder is under /private, a home folder isn't")
    func underPrivate() {
        #expect(MirrorScope.isUnderPrivate(FileManager.default.temporaryDirectory))
        #expect(MirrorScope.isUnderPrivate(URL(fileURLWithPath: "/tmp")))
        #expect(!MirrorScope.isUnderPrivate(FileManager.default.homeDirectoryForCurrentUser))
    }
}
