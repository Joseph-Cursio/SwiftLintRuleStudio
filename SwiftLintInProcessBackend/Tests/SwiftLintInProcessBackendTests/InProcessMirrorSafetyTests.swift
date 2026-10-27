import Foundation
@testable import SwiftLintInProcessBackend
import SwiftLintRuleStudioCore
import Testing

/// In-process, SwiftLint ends the process — the app — on a config it can't use: a pinned
/// `swiftlint_version` that doesn't match, or one it rejects. Every config a lint can load
/// must be checked first, including those beside a simulation mirror's lint root.
@MainActor
@Suite(.serialized)
struct InProcessMirrorSafetyTests {
    private static let source = "import Foundation\n\nlet number = NSNumber(value: 1) as! Int\n"

    private struct Layout {
        /// Clean this up.
        let base: URL
        let workspace: URL
    }

    /// A workspace at `<base>/ws` with `excluded` set, so SwiftLint follows its link
    /// `Sources/Vendor -> <base>/shared`, whose config — or the one above it — pins a version.
    private func makeLayout(pinAbove: Bool) throws -> Layout {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessMirrorSafetyTests-\(UUID().uuidString)", isDirectory: true)
        let workspace = base.appendingPathComponent("ws", isDirectory: true)
        let shared = base.appendingPathComponent("shared", isDirectory: true)
        for folder in [workspace.appendingPathComponent("Sources"), shared] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let files = [
            (workspace.appendingPathComponent(".swiftlint.yml"), "excluded:\n  - Pods\n"),
            (workspace.appendingPathComponent("Sources/A.swift"), Self.source),
            (shared.appendingPathComponent("V.swift"), Self.source),
            ((pinAbove ? base : shared).appendingPathComponent(".swiftlint.yml"), "swiftlint_version: 0.1.0\n")
        ]
        for (url, content) in files {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        try FileManager.default.createSymbolicLink(
            atPath: workspace.appendingPathComponent("Sources/Vendor").path,
            withDestinationPath: "../../shared"
        )
        return Layout(base: base, workspace: workspace)
    }

    @Test(
        "A config outside the workspace, in a linked folder or above it, is checked like a nested one",
        arguments: [false, true]
    )
    func outsideConfigIsChecked(pinAbove: Bool) throws {
        let layout = try makeLayout(pinAbove: pinAbove)
        defer { try? FileManager.default.removeItem(at: layout.base) }

        #expect(throws: (any Error).self) {
            try InProcessConfiguration.checkNestedConfigs(in: layout.workspace)
        }
    }

    @Test(
        "A mirrored config SwiftLint would reject fails the simulation instead of ending the app",
        arguments: [false, true]
    )
    func badMirroredConfigFailsTheSimulation(pinAbove: Bool) async throws {
        let layout = try makeLayout(pinAbove: pinAbove)
        defer { try? FileManager.default.removeItem(at: layout.base) }

        // The guard first, on its own: were it to miss this config, linting below would end the
        // test process rather than fail the test.
        let guarded = (try? InProcessConfiguration.checkNestedConfigs(in: layout.workspace)) == nil
        guard guarded else {
            Issue.record("the nested-config guard let a pinned outside config through; not linting")
            return
        }

        let batch = try await ImpactSimulator(swiftLintCLI: SwiftLintInProcessActor()).simulateRules(
            ruleIds: ["force_cast"],
            workspace: Workspace(path: layout.workspace),
            baseConfigPath: nil
        )

        let result = try #require(batch.results.first)
        guard case .failed(let reason) = result.measurement else {
            Issue.record("measured \(result.violationCount) with a config SwiftLint rejects")
            return
        }
        #expect(reason?.contains("0.1.0") == true)
    }

    @Test("A cancelled simulation lint stops waiting at once, and the lint it left is waited for before cleanup")
    func cancelledSimulationLintIsAbandoned() async throws {
        let layout = try makeLayout(pinAbove: false)
        defer { try? FileManager.default.removeItem(at: layout.base) }
        try FileManager.default.removeItem(at: layout.workspace.appendingPathComponent("Sources/Vendor"))
        let workspace = layout.workspace
        let backend = SwiftLintInProcessActor()

        let lint = Task { try await backend.executeSimulationLintCommand(workspacePath: workspace) }
        lint.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await lint.value
        }
        await backend.waitForAbandonedLints(at: workspace)
    }
}
