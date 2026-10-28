//
//  SimulationWorkspacePrivateLoopTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Under /private SwiftLint skips no symlink `excluded` names, but an excluded folder on the
//  way to one still keeps it out. These pin when a loop under /private fails the simulation,
//  and what its reason says to do, against what `swiftlint lint` does in /tmp — and which
//  links the mirror keeps, there and elsewhere, against what it lints.
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

    /// A workspace at `<base>/<workspace>` with `config`, and `<base>/kit` beside it holding `B.swift`.
    private func makeLayout(
        config: String,
        workspace: String = "ws",
        base: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowSymlinkTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    ) throws -> Layout {
        let layout = Layout(base: base, workspace: base.appendingPathComponent(workspace, isDirectory: true))
        try write(config, to: layout.workspace.appendingPathComponent(".swiftlint.yml"))
        try write("let a = 1\n", to: layout.workspace.appendingPathComponent("Sources/A.swift"))
        try write("let b = 1\n", to: base.appendingPathComponent("kit/B.swift"))
        return layout
    }

    /// The mirror plan for `layout`'s workspace: under /private, as a test's temp folder is,
    /// unless `underPrivate` is false.
    private func plan(_ layout: Layout, underPrivate: Bool = true) throws -> WorkspaceMirrorPlan {
        let scope = try MirrorScope.make(
            workspaceRoot: layout.workspace,
            rootConfig: layout.workspace.appendingPathComponent(".swiftlint.yml")
        )
        try #require(scope.isUnderPrivate, "the temporary directory isn't under /private")
        return try WorkspaceMirrorPlan.make(for: underPrivate ? scope : scope.underPrivate(false))
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
        // Excluding the folder that holds it does keep SwiftLint out; see the cases below.
        #expect(error?.reason.contains("exclude Sources, the folder that holds it, or remove the link") == true)
        #expect(error?.reason.contains("Add it to `excluded`") == false)
    }

    @Test(
        "under /private a loop an excluded folder on the way keeps SwiftLint out of is left out",
        arguments: PrivateLoop.keptOut
    )
    func keptOutLoop(_ loopCase: PrivateLoop.Case) throws {
        try check(loopCase)
    }

    @Test(
        "under /private a loop no exclusion keeps SwiftLint out of fails the simulation",
        arguments: PrivateLoop.notKeptOut
    )
    func notKeptOutLoop(_ loopCase: PrivateLoop.Case) throws {
        try check(loopCase)
    }

    @Test(
        "under /private a loop's reason names a folder to exclude only when that would work",
        arguments: PrivateLoop.advice
    )
    func loopAdvice(_ loopCase: PrivateLoop.Case) throws {
        try check(loopCase)
    }

    @Test(
        "under /private walk starts, every route and real paths decide a loop as SwiftLint does",
        arguments: PrivateLoop.routes
    )
    func loopRoutes(_ loopCase: PrivateLoop.Case) throws {
        try check(loopCase)
    }

    @Test(
        "the mirror reproduces what keeps SwiftLint out of a loop, and keeps the links it follows",
        arguments: PrivateLoop.mirror
    )
    func loopInMirror(_ loopCase: PrivateLoop.Case) throws {
        try check(loopCase)
    }

    @Test(
        "the mirror keeps the links SwiftLint goes through on the way to what `included` names",
        arguments: PrivateLoop.throughLinks
    )
    func linksOnTheWay(_ loopCase: PrivateLoop.Case) throws {
        try check(loopCase)
    }

    private func check(_ loopCase: PrivateLoop.Case) throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowSymlinkTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let config = loopCase.config.replacingOccurrences(of: "<base>", with: base.path)
        let layout = try makeLayout(config: config, workspace: loopCase.workspace, base: base)
        defer { try? FileManager.default.removeItem(at: layout.base) }
        for file in loopCase.files {
            try write("let x = 1\n", to: layout.base.appendingPathComponent(file))
        }
        for link in loopCase.links {
            try self.link(layout.base.appendingPathComponent(link.path), to: link.destination)
        }

        switch loopCase.outcome {
        case .leftOut:
            let plan = try plan(layout, underPrivate: loopCase.underPrivate)
            #expect(!plan.links.contains { $0.path.hasSuffix("/loop") }, "\(plan.links.map(\.path))")
        case .refused(let advice):
            let error = #expect(throws: MirrorUnsupportedSetupError.self) {
                _ = try plan(layout, underPrivate: loopCase.underPrivate)
            }
            if let advice {
                #expect(error?.reason.contains(advice) == true, "\(error?.reason ?? "")")
                #expect(error?.reason.contains("Add it to `excluded`") == false)
            }
        case .keeps(let path):
            let plan = try plan(layout, underPrivate: loopCase.underPrivate)
            #expect(plan.links.contains { $0.path == path }, "\(plan.links.map(\.path))")
        }
    }
}
