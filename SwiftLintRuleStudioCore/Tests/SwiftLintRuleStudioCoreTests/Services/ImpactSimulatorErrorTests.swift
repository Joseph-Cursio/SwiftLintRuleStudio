//
//  ImpactSimulatorErrorTests.swift
//  SwiftLintRuleStudioTests
//
//  Error handling tests for ImpactSimulator
//

import Foundation
import SwiftLintCLISeam
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct ImpactSimulatorErrorTests {
    @Test("ImpactSimulator handles simulation errors gracefully")
    func testHandlesSimulationErrors() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        _ = try ImpactSimulatorTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let x = 1\n"
        )

        let workspace = Workspace(path: tempDir)
        let mockCLI = MockSwiftLintCLIActor(shouldFail: true)

        await #expect(throws: Error.self) {
            _ = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
                try await simulator.simulateRule(
                    ruleId: "test_rule",
                    workspace: workspace,
                    baseConfigPath: nil
                )
            }
        }
    }

    @Test("ImpactSimulator handles errors in batch simulation")
    func testHandlesBatchErrors() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        _ = try ImpactSimulatorTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let x = 1\n"
        )

        let workspace = Workspace(path: tempDir)
        let mockCLI = MockSwiftLintCLIActor(shouldFail: true)

        let batchResult = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRules(
                ruleIds: ["rule1", "rule2"],
                workspace: workspace,
                baseConfigPath: nil
            )
        }

        let counts = batchResult.results.map(\.violationCount)
        #expect(counts.count == 2)
        #expect(counts.allSatisfy { $0 == -1 })
    }

    @Test("A failed rule in a batch carries the error's description and is never safe")
    func batchFailureCarriesReason() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        let workspace = Workspace(path: tempDir)
        let mockCLI = MockSwiftLintCLIActor(shouldFail: true)

        let batchResult = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRules(
                ruleIds: ["rule1"],
                workspace: workspace,
                baseConfigPath: nil
            )
        }

        let result = try #require(batchResult.results.first)
        let expectedReason = SwiftLintError.executionFailed(message: "Mock failure").localizedDescription
        #expect(result.measurement == .failed(reason: expectedReason))
        #expect(result.isMeasured == false)
        #expect(result.isSafe == false)
        #expect(result.hasViolations == false)
        #expect(batchResult.safeRules.isEmpty)
    }

    @Test("A cancelled batch stops instead of linting the remaining rules")
    func cancelledBatchStops() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLIActor(violations: [])
        let simulator = ImpactSimulator(swiftLintCLI: mockCLI)

        // Cancelled before it starts, as an audit is when its workspace closes.
        let batch = Task {
            try await simulator.simulateRules(
                ruleIds: ["rule1", "rule2"],
                workspace: Workspace(path: tempDir),
                baseConfigPath: nil
            )
        }
        batch.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await batch.value
        }
    }

    @Test("A lint cancelled mid-rule cancels the batch rather than recording a failure")
    func cancellationInsideALintIsNotAFailure() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }
        let mockCLI = MockSwiftLintCLIActor()
        await mockCLI.setLintCommandHandler { @Sendable _, _ in throw CancellationError() }

        await #expect(throws: CancellationError.self) {
            _ = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
                try await simulator.simulateRules(
                    ruleIds: ["rule1"],
                    workspace: Workspace(path: tempDir),
                    baseConfigPath: nil
                )
            }
        }
    }

    @Test("findSafeRules never offers a rule whose simulation failed")
    func findSafeRulesSkipsFailures() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        let workspace = Workspace(path: tempDir)
        let mockCLI = MockSwiftLintCLIActor(shouldFail: true)

        let safeRuleIds = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.findSafeRules(
                workspace: workspace,
                baseConfigPath: nil,
                disabledRuleIds: ["rule1", "rule2"]
            )
        }

        #expect(safeRuleIds.isEmpty)
    }
}
