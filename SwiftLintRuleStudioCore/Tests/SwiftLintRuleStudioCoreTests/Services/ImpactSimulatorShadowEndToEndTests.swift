//
//  ImpactSimulatorShadowEndToEndTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  End-to-end proof that a simulated/audited rule actually fires through the
//  shadow workspace, driving the real swiftlint binary. Before the shadow-tree
//  fix the temp config was ignored (SwiftLint used the workspace's own config
//  from cwd), so a disabled rule reported 0 violations. These tests assert the
//  opposite — they fail on the old code and pass on the new.
//
//  Requires SwiftLint to be installed.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

// SwiftLintCLIActor is an actor; CacheManager trips a Swift 6 false positive, so
// (as in SwiftLintCLIIntegrationTests) the struct is marked @MainActor.
@MainActor
struct ImpactSimulatorShadowEndToEndTests {

    nonisolated private func isSwiftLintAvailable() -> Bool {
        ["/opt/homebrew/bin/swiftlint", "/usr/local/bin/swiftlint", "/usr/bin/swiftlint"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func makeTempWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowEndToEndTests", isDirectory: true)
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

    private func makeSimulator() -> ImpactSimulator {
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowEndToEndTests", isDirectory: true)
            .appendingPathComponent("cache-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return ImpactSimulator(swiftLintCLI: SwiftLintCLIActor(cacheManager: CacheManager(cacheDirectory: cacheDir)))
    }

    /// A snippet that trips `force_cast` (SwiftLint is syntactic — it needn't compile).
    private let forceCastSource = """
    let anyValue: Any = 1
    let casted = anyValue as! Int
    _ = casted
    """

    @Test("a rule disabled in the workspace config still fires in simulation")
    func disabledRuleFiresThroughShadow() async throws {
        guard isSwiftLintAvailable() else {
            #expect(Bool(false), "SwiftLint not installed - skipping integration test")
            return
        }

        let workspaceRoot = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        // force_cast is OFF in the workspace's own config — the exact situation
        // "simulate impact" targets.
        try write("disabled_rules:\n  - force_cast\n", to: workspaceRoot.appendingPathComponent(".swiftlint.yml"))
        try write(forceCastSource, to: workspaceRoot.appendingPathComponent("Sources/Offender.swift"))

        let workspace = Workspace(path: workspaceRoot)
        let result = try await makeSimulator().simulateRule(
            ruleId: "force_cast",
            workspace: workspace,
            baseConfigPath: workspace.configPath
        )

        #expect(result.violationCount > 0)
        #expect(result.violations.allSatisfy { $0.ruleID == "force_cast" })
        #expect(result.affectedFiles.contains { $0.contains("Offender.swift") })
    }

    @Test("a rule disabled by a nested config still fires (merge into nested)")
    func ruleDisabledByNestedConfigStillFires() async throws {
        guard isSwiftLintAvailable() else {
            #expect(Bool(false), "SwiftLint not installed - skipping integration test")
            return
        }

        let workspaceRoot = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        // Root leaves force_cast at its default (on); a nested config turns it off
        // for the Legacy subtree. Both files violate it.
        try write("", to: workspaceRoot.appendingPathComponent(".swiftlint.yml"))
        try write(forceCastSource, to: workspaceRoot.appendingPathComponent("Sources/Root.swift"))
        try write(
            "disabled_rules:\n  - force_cast\n",
            to: workspaceRoot.appendingPathComponent("Legacy/.swiftlint.yml")
        )
        try write(forceCastSource, to: workspaceRoot.appendingPathComponent("Legacy/Old.swift"))

        let workspace = Workspace(path: workspaceRoot)
        let result = try await makeSimulator().simulateRule(
            ruleId: "force_cast",
            workspace: workspace,
            baseConfigPath: workspace.configPath
        )

        // Both the root file and the nested-disabled file are counted, because
        // the mirror enables the rule in every config.
        #expect(result.affectedFiles.contains { $0.contains("Root.swift") })
        #expect(result.affectedFiles.contains { $0.contains("Old.swift") })
    }
}
