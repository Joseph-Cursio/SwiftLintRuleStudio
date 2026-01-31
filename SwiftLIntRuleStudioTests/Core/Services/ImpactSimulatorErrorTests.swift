//
//  ImpactSimulatorErrorTests.swift
//  SwiftLIntRuleStudioTests
//
//  Error handling tests for ImpactSimulator
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

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

        let workspace = await MainActor.run { Workspace(path: tempDir) }
        let mockCLI = MockSwiftLintCLI(shouldFail: true)

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

        let workspace = await MainActor.run { Workspace(path: tempDir) }
        let mockCLI = MockSwiftLintCLI(shouldFail: true)

        let batchResult = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRules(
                ruleIds: ["rule1", "rule2"],
                workspace: workspace,
                baseConfigPath: nil
            )
        }

        let counts = await MainActor.run { batchResult.results.map { $0.violationCount } }
        #expect(counts.count == 2)
        #expect(counts.allSatisfy { $0 == -1 })
    }
}
