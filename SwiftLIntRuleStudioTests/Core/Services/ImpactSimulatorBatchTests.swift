//
//  ImpactSimulatorBatchTests.swift
//  SwiftLIntRuleStudioTests
//
//  Batch simulation tests
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

struct ImpactSimulatorBatchTests {
    private struct ProgressEvent {
        let current: Int
        let total: Int
        let ruleId: String
    }

    private struct ProgressSnapshot {
        let count: Int
        let events: [ProgressEvent]
    }
    @Test("ImpactSimulator simulates multiple rules")
    func testSimulateMultipleRules() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        _ = try ImpactSimulatorTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let x = 1\n"
        )

        let violations = [
            Violation(ruleID: "rule1", filePath: "Test.swift", line: 1, severity: .warning, message: "one"),
            Violation(ruleID: "rule2", filePath: "Test.swift", line: 2, severity: .error, message: "two")
        ]

        let workspace = await MainActor.run { Workspace(path: tempDir) }
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLI(violations: violations)

        let batchResult = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRules(
                ruleIds: ["rule1", "rule2"],
                workspace: workspace,
                baseConfigPath: nil
            )
        }

        let results = await MainActor.run { batchResult.results }
        let ruleIds = await MainActor.run { results.map { $0.ruleId } }
        #expect(results.count == 2)
        #expect(ruleIds.contains("rule1"))
        #expect(ruleIds.contains("rule2"))
    }

    @Test("ImpactSimulator tracks progress during batch simulation")
    func testBatchProgress() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        _ = try ImpactSimulatorTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let x = 1\n"
        )

        let workspace = await MainActor.run { Workspace(path: tempDir) }
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLI(violations: [])

        let progressValues = try await ImpactSimulatorTestHelpers.withImpactSimulator(
            swiftLintCLI: mockCLI
        ) { simulator in
            var progress: [ProgressEvent] = []
            let batchResult = try await simulator.simulateRules(
                ruleIds: ["rule1", "rule2", "rule3"],
                workspace: workspace,
                baseConfigPath: nil
            ) { current, total, ruleId in
                progress.append(
                    ProgressEvent(
                        current: current,
                        total: total,
                        ruleId: ruleId
                    )
                )
            }
            let count = await MainActor.run { batchResult.results.count }
            return ProgressSnapshot(count: count, events: progress)
        }

        #expect(progressValues.count == 3)
        #expect(progressValues.events.last?.total == 3)
    }

    @Test("ImpactSimulator finds safe rules with zero violations")
    func testFindSafeRules() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        _ = try ImpactSimulatorTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let x = 1\n"
        )

        let workspace = await MainActor.run { Workspace(path: tempDir) }
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLI(violations: [])

        let results = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.findSafeRules(
                workspace: workspace,
                baseConfigPath: nil,
                disabledRuleIds: ["rule1", "rule2"]
            )
        }

        #expect(results.count == 2)
        #expect(results.contains("rule1"))
        #expect(results.contains("rule2"))
    }

    @Test("ImpactSimulator filters out rules with violations from safe rules")
    func testFilterRulesWithViolations() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        _ = try ImpactSimulatorTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let x = 1\n"
        )

        let violations = [
            Violation(ruleID: "rule1", filePath: "Test.swift", line: 1, severity: .warning, message: "one")
        ]

        let workspace = await MainActor.run { Workspace(path: tempDir) }
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLI(violations: violations)

        let results = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.findSafeRules(
                workspace: workspace,
                baseConfigPath: nil,
                disabledRuleIds: ["rule1", "rule2"]
            )
        }

        #expect(results.contains("rule2"))
        #expect(results.contains("rule1") == false)
    }
}
