//
//  ImpactSimulatorMirrorFailureTests.swift
//  SwiftLintRuleStudioTests
//
//  A batch whose mirror can't be built must fail its rules, never count them clean.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

/// A builder whose mirror can't be built — the workspace's links lead too far, say.
private struct FailingWorkspaceBuilder: SimulationWorkspaceBuilding {
    struct MirrorFailure: LocalizedError {
        var errorDescription: String? { "The mirror couldn't be built" }
    }

    func makeWorkspace(for _: Workspace, baseConfigPath _: URL?) throws -> SimulationWorkspace {
        throw MirrorFailure()
    }
}

struct ImpactSimulatorMirrorFailureTests {
    @Test("A batch whose mirror can't be built fails each rule that needed a lint, with the reason")
    func mirrorFailureFailsEachRule() async throws {
        let simulator = ImpactSimulator(
            swiftLintCLI: MockSwiftLintCLIActor(),
            workspaceBuilder: FailingWorkspaceBuilder()
        )

        let batch = try await simulator.simulateRules(
            ruleIds: ["force_cast", "unused_import"],
            workspace: Workspace(path: FileManager.default.temporaryDirectory),
            baseConfigPath: nil,
            classification: RuleClassification(analyzerRuleIds: ["unused_import"])
        )

        let measurements = Dictionary(uniqueKeysWithValues: batch.results.map { ($0.ruleId, $0.measurement) })
        #expect(measurements["force_cast"] == .failed(reason: "The mirror couldn't be built"))
        #expect(measurements["unused_import"] == .unmeasurable(.analyzerRule), "still told apart")
        #expect(batch.safeRules.isEmpty)
    }
}
