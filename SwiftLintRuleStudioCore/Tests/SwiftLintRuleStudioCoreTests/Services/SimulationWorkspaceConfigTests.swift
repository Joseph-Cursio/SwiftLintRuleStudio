//
//  SimulationWorkspaceConfigTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The mirror reproduces which configuration SwiftLint gives each file — including the ones it
//  finds beside and above the workspace — or refuses a setup it can't.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct SimulationWorkspaceConfigTests {

    // MARK: - Helpers

    /// Puts the mirrors a test makes in its own temp folder, so it can look around them.
    nonisolated private final class IsolatedFileManager: FileManager, @unchecked Sendable {
        let folder: URL

        init(folder: URL) {
            self.folder = folder
            super.init()
        }

        override var temporaryDirectory: URL { folder }
    }

    /// `<base>/ws` holding `.swiftlint.yml` and `Sources/A.swift`, mirrored into a temp folder
    /// of its own — not in `<base>`, whose configs would be above every mirror.
    private struct Layout {
        let base: URL
        let workspace: URL
        let fileManager: IsolatedFileManager

        func remove() {
            try? FileManager.default.removeItem(at: base)
            try? FileManager.default.removeItem(at: fileManager.folder)
        }

        var containers: [URL] {
            let parent = fileManager.folder.appendingPathComponent("SwiftLintRuleStudio")
            return (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
        }
    }

    private func makeLayout(config: String) throws -> Layout {
        let id = UUID().uuidString
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowConfigTests-\(id)", isDirectory: true)
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowConfigTests-mirrors-\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let layout = Layout(
            base: base,
            workspace: base.appendingPathComponent("ws", isDirectory: true),
            fileManager: IsolatedFileManager(folder: temp)
        )
        try write(config, to: layout.workspace.appendingPathComponent(".swiftlint.yml"))
        try write("let a = 1\n", to: layout.workspace.appendingPathComponent("Sources/A.swift"))
        return layout
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeShadow(_ layout: Layout) throws -> SimulationWorkspace {
        let shadow = try SimulationWorkspaceBuilder(fileManager: layout.fileManager)
            .makeWorkspace(for: Workspace(path: layout.workspace), baseConfigPath: nil)
        try shadow.applyRule("force_cast", isOptIn: false, isAnalyzer: false, parameterOverrides: nil)
        return shadow
    }

    private func loadConfig(at url: URL) throws -> YAMLConfigurationEngine.YAMLConfig {
        try YAMLConfigurationEngine.loadConfig(at: url)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Configs SwiftLint can't read, or reads as empty

    @Test("a nested config SwiftLint can't read fails the simulation and leaves no container")
    func unreadableNestedConfigFails() throws {
        let layout = try makeLayout(config: "disabled_rules:\n  - todo\n")
        defer { layout.remove() }
        try write("line_length: [\n", to: layout.workspace.appendingPathComponent("Sources/.swiftlint.yml"))

        // SwiftLint stops on it; skipping it would hand the folder the root config instead.
        #expect(throws: MirrorUnsupportedSetupError.self) {
            _ = try makeShadow(layout)
        }
        #expect(layout.containers.isEmpty)
    }

    @Test("a root config SwiftLint can't read is replaced by the defaults, as SwiftLint replaces it")
    func unreadableRootConfigFallsBack() throws {
        let layout = try makeLayout(config: "line_length: [\n")
        defer { layout.remove() }

        let shadow = try makeShadow(layout)
        defer { shadow.cleanup() }

        #expect(try loadConfig(at: shadow.root.appendingPathComponent(".swiftlint.yml")).disabledRules == nil)
    }

    @Test("a nested config with nothing but comments is mirrored, so lookups stop there as in SwiftLint")
    func commentOnlyNestedConfigIsMirrored() throws {
        let layout = try makeLayout(config: "disabled_rules:\n  - todo\n")
        defer { layout.remove() }
        try write("line_length: 60\n", to: layout.workspace.appendingPathComponent("Sources/.swiftlint.yml"))
        try write("# nothing yet\n", to: layout.workspace.appendingPathComponent("Sources/Sub/.swiftlint.yml"))
        try write("let b = 1\n", to: layout.workspace.appendingPathComponent("Sources/Sub/B.swift"))

        let shadow = try makeShadow(layout)
        defer { shadow.cleanup() }

        // Left out, `Sub` would get `Sources`' line length; SwiftLint gives it the root's.
        #expect(exists(shadow.root.appendingPathComponent("Sources/Sub/.swiftlint.yml")))
    }

    // MARK: - Configs beside and above the workspace

    @Test("a parent config beside the workspace is mirrored beside the lint root, and the rule enabled in it")
    func parentConfigBesideIsMirrored() throws {
        let layout = try makeLayout(config: "parent_config: ../base.yml\n")
        defer { layout.remove() }
        try write("disabled_rules:\n  - force_cast\n", to: layout.base.appendingPathComponent("base.yml"))

        let shadow = try makeShadow(layout)
        defer { shadow.cleanup() }

        let parent = shadow.root.deletingLastPathComponent().appendingPathComponent("base.yml")
        #expect(try loadConfig(at: parent).disabledRules?.contains("force_cast") != true)
        let root = try String(contentsOf: shadow.root.appendingPathComponent(".swiftlint.yml"), encoding: .utf8)
        #expect(root.contains("parent_config: ../base.yml"))
    }

    @Test("a parent config in the folder holding the workspace isn't mistaken for a config above it")
    func parentConfigAtTheContainerIsPassedOver() throws {
        // SwiftLint passes over the configs that make up the configuration when it looks for a
        // file's nested config; so the hosted folder below finds nothing above it.
        let layout = try makeLayout(config: "parent_config: ../.swiftlint.yml\nincluded:\n  - Sources\n  - ../Shared\n")
        defer { layout.remove() }
        try write("line_length: 100\n", to: layout.base.appendingPathComponent(".swiftlint.yml"))
        try write("let s = 1\n", to: layout.base.appendingPathComponent("Shared/S.swift"))

        let shadow = try makeShadow(layout)
        defer { shadow.cleanup() }

        let container = shadow.root.deletingLastPathComponent()
        #expect(exists(container.appendingPathComponent("Shared/S.swift")))
        let parent = try String(contentsOf: container.appendingPathComponent(".swiftlint.yml"), encoding: .utf8)
        #expect(parent.contains("line_length: 100"))
    }

    @Test("an outside file a link points at, beside the workspace, is copied to its own place there")
    func fileBesideTheWorkspaceKeepsItsPlace() throws {
        // So `excluded: [../Shared/Sources]` excludes the copy, as it excludes the real file.
        let layout = try makeLayout(config: "excluded:\n  - ../Shared/Sources\n")
        defer { layout.remove() }
        try write("let s = 1\n", to: layout.base.appendingPathComponent("Shared/Sources/S.swift"))
        try FileManager.default.createSymbolicLink(
            atPath: layout.workspace.appendingPathComponent("Sources/S.swift").path,
            withDestinationPath: "../../Shared/Sources/S.swift"
        )

        let shadow = try makeShadow(layout)
        defer { shadow.cleanup() }

        let copy = shadow.root.deletingLastPathComponent().appendingPathComponent("Shared/Sources/S.swift")
        #expect(exists(copy))
        #expect(
            shadow.root.appendingPathComponent("Sources/S.swift").resolvingSymlinksInPath().path
                == copy.resolvingSymlinksInPath().path
        )
    }

    @Test("under /private the nearest config above the workspace is mirrored at the container")
    func configAboveIsMirroredUnderPrivate() throws {
        // There SwiftLint climbs out of the workspace for the files in it, as it climbs out of a
        // mirror's lint root under /private with it.
        let layout = try makeLayout(config: "disabled_rules:\n  - todo\n")
        defer { layout.remove() }
        try write("line_length: 70\n", to: layout.base.appendingPathComponent(".swiftlint.yml"))

        let shadow = try makeShadow(layout)
        defer { shadow.cleanup() }

        let above = shadow.root.deletingLastPathComponent().appendingPathComponent(".swiftlint.yml")
        #expect(try String(contentsOf: above, encoding: .utf8).contains("line_length: 70"))
    }

    @Test("a config above the folder mirrors are made in fails a simulation that would climb to it")
    func strayConfigAboveTheMirrorsFails() throws {
        let layout = try makeLayout(config: "disabled_rules:\n  - todo\n")
        defer { layout.remove() }
        try write("line_length: 10\n", to: layout.fileManager.folder.appendingPathComponent(".swiftlint.yml"))

        #expect(throws: MirrorUnsupportedSetupError.self) {
            _ = try makeShadow(layout)
        }
        #expect(layout.containers.isEmpty)
    }

    // MARK: - Where mirrors go

    @Test("a workspace under /private is mirrored in the temp folder, any other in the caches folder")
    func mirrorsFolder() throws {
        let layout = try makeLayout(config: "disabled_rules:\n  - todo\n")
        defer { layout.remove() }
        let scope = try MirrorScope.make(workspaceRoot: layout.workspace, rootConfig: nil)

        let temp = try SimulationWorkspaceBuilder.mirrorsFolder(for: scope, fileManager: layout.fileManager)
        #expect(temp == layout.fileManager.folder.appendingPathComponent("SwiftLintRuleStudio", isDirectory: true))

        let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let home = try SimulationWorkspaceBuilder.mirrorsFolder(for: scope.underPrivate(false), fileManager: .default)
        #expect(home.path.hasPrefix(caches.path + "/"))
        #expect(!MirrorScope.isUnderPrivate(caches))
    }

    @Test("a workspace on a volume that tells names apart by case is mirrored on one that does too, or refused")
    func caseSensitiveVolume() throws {
        let layout = try makeLayout(config: "disabled_rules:\n  - todo\n")
        defer { layout.remove() }
        let scope = try MirrorScope.make(workspaceRoot: layout.workspace, rootConfig: nil)
        let workspace = scope.workspaceRoot

        // The usual folder matches: it is used.
        let same = try SimulationWorkspaceBuilder.mirrorsFolder(for: scope, fileManager: layout.fileManager) { _ in
            false
        }
        #expect(same == layout.fileManager.folder.appendingPathComponent("SwiftLintRuleStudio", isDirectory: true))

        // It doesn't, but the workspace's volume has a temporary folder that does: that is used.
        let onVolume = try SimulationWorkspaceBuilder.mirrorsFolder(for: scope, fileManager: .default) { url in
            url.path.hasPrefix(workspace) || url.path.contains("TemporaryItems")
        }
        #expect(onVolume.path.contains("TemporaryItems"))

        // Nowhere matches: refused.
        #expect(throws: MirrorUnsupportedSetupError.self) {
            try SimulationWorkspaceBuilder.mirrorsFolder(for: scope, fileManager: .default) { url in
                url.path.hasPrefix(workspace)
            }
        }
    }

    @Test("a workspace under /private, with nowhere under /private to mirror it, is refused")
    func noPrivateFolderToMirrorIn() throws {
        let layout = try makeLayout(config: "disabled_rules:\n  - todo\n")
        defer { layout.remove() }
        let scope = try MirrorScope.make(workspaceRoot: layout.workspace, rootConfig: nil)
        // As in the sandboxed edition, whose temp folder is in its container.
        let sandboxed = IsolatedFileManager(folder: FileManager.default.homeDirectoryForCurrentUser)

        #expect(throws: MirrorUnsupportedSetupError.self) {
            try SimulationWorkspaceBuilder.mirrorsFolder(for: scope, fileManager: sandboxed)
        }
    }
}
