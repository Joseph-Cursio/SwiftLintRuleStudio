//
//  SimulationWorkspaceSymlinkTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The mirror keeps a workspace's symlinks as symlinks — into the mirror, or into a copy of a
//  folder outside the workspace kept beside it — so SwiftLint applies its own link rules there
//  as it does in the real workspace. InProcessSymlinkAgreementTests checks the counts against
//  SwiftLint itself; these check the shape that makes that possible.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct SimulationWorkspaceSymlinkTests {

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

    private func makeShadow(for workspace: URL, applying ruleId: String = "force_cast") throws -> SimulationWorkspace {
        let shadow = try SimulationWorkspaceBuilder().makeWorkspace(
            for: Workspace(path: workspace),
            baseConfigPath: nil
        )
        try shadow.applyRule(ruleId, isOptIn: false, isAnalyzer: false, parameterOverrides: nil)
        return shadow
    }

    // MARK: - Folder links

    @Test("a link to a folder outside the workspace is kept, pointing at a copy outside the lint root")
    func outsideFolderLinkPointsAtACopy() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try write("disabled_rules:\n  - force_cast\n", to: layout.kit.appendingPathComponent(".swiftlint.yml"))
        try link(layout.workspace.appendingPathComponent("Sources/Shared"), to: "../../kit")

        let shadow = try makeShadow(for: layout.workspace)
        defer { shadow.cleanup() }

        let mirroredLink = shadow.root.appendingPathComponent("Sources/Shared")
        #expect(isSymlink(mirroredLink), "a link, so SwiftLint applies its own link rules to it")
        let copy = URL(fileURLWithPath: resolved(mirroredLink))
        #expect(!copy.path.hasPrefix(resolved(shadow.root) + "/"), "outside the lint root, as the real folder is")
        #expect(copy.path != resolved(layout.kit), "a copy, not the user's folder")
        #expect(try String(contentsOf: copy.appendingPathComponent("B.swift"), encoding: .utf8) == "let b = 1\n")
        // The config inside it is mirrored like any nested config — as it is, as Enable leaves it.
        let copiedConfig = try loadConfig(at: copy.appendingPathComponent(".swiftlint.yml"))
        #expect(copiedConfig.disabledRules == ["force_cast"])
        #expect(try loadConfig(at: layout.kit.appendingPathComponent(".swiftlint.yml")).disabledRules == ["force_cast"])
    }

    @Test("a link to a folder in the workspace points at that folder's mirror")
    func insideFolderLinkPointsAtTheMirror() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try link(layout.workspace.appendingPathComponent("Linked"), to: "Sources")

        let shadow = try makeShadow(for: layout.workspace)
        defer { shadow.cleanup() }

        let mirroredLink = shadow.root.appendingPathComponent("Linked")
        #expect(isSymlink(mirroredLink))
        #expect(resolved(mirroredLink) == resolved(shadow.root.appendingPathComponent("Sources")))
    }

    /// SwiftLint reports files behind a link at their real path when it follows one, and drops
    /// a file it reaches twice; one copy per real folder keeps that true in the mirror.
    @Test("two links into one outside folder, or into a folder inside it, reach one copy")
    func linksIntoOneFolderShareACopy() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try write("let c = 1\n", to: layout.kit.appendingPathComponent("Sub/C.swift"))
        try link(layout.workspace.appendingPathComponent("App/Shared"), to: "../../kit")
        try link(layout.workspace.appendingPathComponent("Widget/Shared"), to: "../../kit")
        try link(layout.workspace.appendingPathComponent("Widget/Sub"), to: "../../kit/Sub")

        let shadow = try makeShadow(for: layout.workspace)
        defer { shadow.cleanup() }

        let app = resolved(shadow.root.appendingPathComponent("App/Shared"))
        #expect(resolved(shadow.root.appendingPathComponent("Widget/Shared")) == app)
        #expect(resolved(shadow.root.appendingPathComponent("Widget/Sub")) == app + "/Sub")
    }

    @Test("a folder link SwiftLint may follow is kept as a link, however the config gets there")
    func followableFolderLinksAreKept() throws {
        // SwiftLint decides in the mirror, as it does in the workspace: `included: [Sources/**]`
        // with an exclusion follows the link, `included: [Sources/**/*.swift]` never does.
        let configs = [
            "excluded:\n  - Nope\n",
            "included:\n  - Sources/**\nexcluded:\n  - Sources/Generated\n",
            "included:\n  - Sources\n  - Sources/Shared\nexcluded:\n  - Nope\n",
            "included:\n  - Sources/**/*.swift\n"
        ]
        for config in configs {
            let layout = try makeLayout(config: config)
            defer { try? FileManager.default.removeItem(at: layout.base) }
            try link(layout.workspace.appendingPathComponent("Sources/Shared"), to: "../../kit")

            let shadow = try makeShadow(for: layout.workspace)
            defer { shadow.cleanup() }

            let mirroredLink = shadow.root.appendingPathComponent("Sources/Shared")
            #expect(isSymlink(mirroredLink), "\(config)")
            let mirroredFile = mirroredLink.appendingPathComponent("B.swift")
            #expect(FileManager.default.fileExists(atPath: mirroredFile.path), "\(config)")
        }
    }

    /// With exclusions, SwiftLint reports a followed link's files at their real paths, which an
    /// exclusion written under the link's path doesn't match. Keeping the link keeps that true.
    @Test("an exclusion written under a link's path is kept as written, and the link stays a link")
    func exclusionUnderLinkPathIsKept() throws {
        let layout = try makeLayout(config: "excluded:\n  - Shared/Generated\n")
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try write("let g = 1\n", to: layout.kit.appendingPathComponent("Generated/G.swift"))
        try link(layout.workspace.appendingPathComponent("Shared"), to: "../kit")

        let shadow = try makeShadow(for: layout.workspace)
        defer { shadow.cleanup() }

        #expect(isSymlink(shadow.root.appendingPathComponent("Shared")))
        let rootConfig = try loadConfig(at: shadow.root.appendingPathComponent(".swiftlint.yml"))
        #expect(rootConfig.excluded == ["Shared/Generated"])
    }

    @Test("a link back to a folder that holds it, which SwiftLint excludes, is left out")
    func excludedCyclicLinkIsLeftOut() throws {
        // SwiftLint skips an excluded link before it resolves it — however the pattern names it,
        // outside /private (which a test's temp folder isn't).
        for excluded in ["Sources/loop", "Sources", "**/loop", "Sour*/l?op"] {
            let layout = try makeLayout(config: "excluded:\n  - \"\(excluded)\"\n")
            defer { try? FileManager.default.removeItem(at: layout.base) }
            try write("let a = 1\n", to: layout.workspace.appendingPathComponent("Other/O.swift"))
            try link(layout.workspace.appendingPathComponent("Sources/loop"), to: "..")
            let scope = try MirrorScope.make(
                workspaceRoot: layout.workspace,
                rootConfig: layout.workspace.appendingPathComponent(".swiftlint.yml")
            )

            let plan = try WorkspaceMirrorPlan.make(for: scope.underPrivate(false))

            #expect(plan.sources.contains { $0.path == "ws/Other/O.swift" })
            #expect(!plan.links.contains { $0.path == "ws/Sources/loop" }, "\(excluded)")
        }
    }

    @Test("a link back to a folder that holds it, which SwiftLint follows, fails the simulation")
    func followedCyclicLinkFails() throws {
        // With `excluded` set SwiftLint resolves it and walks the folder again until it crashes:
        // there is no count to measure. Exclusions are case-sensitive, as SwiftLint's are.
        for excluded in ["Nope", "sources/loop", "Sources/loop/x"] {
            let layout = try makeLayout(config: "excluded:\n  - \(excluded)\n")
            defer { try? FileManager.default.removeItem(at: layout.base) }
            try link(layout.workspace.appendingPathComponent("Sources/loop"), to: "..")

            #expect(throws: MirrorUnsupportedSetupError.self, "\(excluded)") {
                try SimulationWorkspaceBuilder().makeWorkspace(
                    for: Workspace(path: layout.workspace),
                    baseConfigPath: nil
                )
            }
        }
    }

    @Test("a link back to a folder that holds it, with nothing excluded, is not followed and not refused")
    func unfollowedCyclicLinkIsFine() throws {
        // Without `excluded`, `subpaths` goes into no link, so the loop is never walked.
        let layout = try makeLayout(config: "disabled_rules:\n  - todo\n")
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try link(layout.workspace.appendingPathComponent("Sources/loop"), to: "..")

        let shadow = try makeShadow(for: layout.workspace)
        defer { shadow.cleanup() }

        #expect(FileManager.default.fileExists(atPath: shadow.root.appendingPathComponent("Sources/A.swift").path))
    }

    @Test("the nearest config above an outside folder is mirrored beside its copy")
    func configAboveOutsideFolderIsMirrored() throws {
        // SwiftLint looks for a file's nested config from its real folder up to `/`.
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try write("disabled_rules:\n  - force_cast\n", to: layout.base.appendingPathComponent(".swiftlint.yml"))
        try link(layout.workspace.appendingPathComponent("Shared"), to: "../kit")

        let shadow = try makeShadow(for: layout.workspace)
        defer { shadow.cleanup() }

        let copy = URL(fileURLWithPath: resolved(shadow.root.appendingPathComponent("Shared")))
        let above = copy.deletingLastPathComponent().appendingPathComponent(".swiftlint.yml")
        #expect(try loadConfig(at: above).disabledRules == ["force_cast"])
    }

    @Test("a linted path in an outside folder's copy maps back to the real path, after the mirror moves")
    func originalPathMapsCopiesBack() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try link(layout.workspace.appendingPathComponent("Shared"), to: "../kit")

        let shadow = try makeShadow(for: layout.workspace)
        defer { shadow.cleanup() }
        try shadow.applyRule("todo", isOptIn: false, isAnalyzer: false, parameterOverrides: nil)

        let copy = resolved(shadow.root.appendingPathComponent("Shared"))
        #expect(shadow.originalPath(ofLinted: copy + "/B.swift") == resolved(layout.kit) + "/B.swift")
        #expect(shadow.originalPath(ofLinted: "/private" + copy + "/B.swift") == resolved(layout.kit) + "/B.swift")
        #expect(shadow.originalPath(ofLinted: resolved(shadow.root) + "/Sources/A.swift") == nil)
    }

    // MARK: - File links

    @Test("a link to an outside file gets the config nearest its real folder")
    func outsideFileLinkGetsItsConfig() throws {
        // SwiftLint lints it at its real path with `excluded` set, under the config there.
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try write("disabled_rules:\n  - force_cast\n", to: layout.kit.appendingPathComponent(".swiftlint.yml"))
        try link(layout.workspace.appendingPathComponent("Sources/E.swift"), to: "../../kit/B.swift")

        let shadow = try makeShadow(for: layout.workspace)
        defer { shadow.cleanup() }

        let copy = URL(fileURLWithPath: resolved(shadow.root.appendingPathComponent("Sources/E.swift")))
        let config = try loadConfig(at: copy.deletingLastPathComponent().appendingPathComponent(".swiftlint.yml"))
        #expect(config.disabledRules == ["force_cast"], "mirrored beside the copy, as it is")
    }

    @Test("a symlinked nested config is mirrored, whatever the root excludes")
    func symlinkedNestedConfigIsMirrored() throws {
        // SwiftLint reads a nested config through a link.
        let layout = try makeLayout(config: "excluded:\n  - Pods\n")
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try write("disabled_rules:\n  - force_cast\n", to: layout.base.appendingPathComponent("config/tests.yml"))
        try write("let t = 1\n", to: layout.workspace.appendingPathComponent("Tests/T.swift"))
        try link(layout.workspace.appendingPathComponent("Tests/.swiftlint.yml"), to: "../../config/tests.yml")

        let shadow = try makeShadow(for: layout.workspace)
        defer { shadow.cleanup() }

        let nested = shadow.root.appendingPathComponent("Tests/.swiftlint.yml")
        #expect(!isSymlink(nested), "written in place, not a link to the user's file")
        #expect(try loadConfig(at: nested).disabledRules == ["force_cast"])
    }

    @Test("a file link points at its mirrored target, or at a copy of an outside one, and a dangling one is left out")
    func fileLinks() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try link(layout.workspace.appendingPathComponent("Alias.swift"), to: "Sources/A.swift")
        try link(layout.workspace.appendingPathComponent("Outside.swift"), to: "../kit/B.swift")
        try link(layout.workspace.appendingPathComponent("Gone.swift"), to: "Nowhere.swift")

        let shadow = try makeShadow(for: layout.workspace)
        defer { shadow.cleanup() }

        let alias = shadow.root.appendingPathComponent("Alias.swift")
        #expect(isSymlink(alias))
        #expect(resolved(alias) == resolved(shadow.root.appendingPathComponent("Sources/A.swift")))
        let outside = shadow.root.appendingPathComponent("Outside.swift")
        #expect(isSymlink(outside), "a link, so SwiftLint lints it where it does in the workspace")
        #expect(try String(contentsOf: outside, encoding: .utf8) == "let b = 1\n")
        #expect(resolved(outside) != resolved(layout.kit.appendingPathComponent("B.swift")), "a copy")
        #expect(!resolved(outside).hasPrefix(resolved(shadow.root) + "/"), "outside the lint root")
        #expect(!FileManager.default.fileExists(atPath: shadow.root.appendingPathComponent("Gone.swift").path))
    }
}
