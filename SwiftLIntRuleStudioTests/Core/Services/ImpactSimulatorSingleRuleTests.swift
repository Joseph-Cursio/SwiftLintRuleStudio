//
//  ImpactSimulatorSingleRuleTests.swift
//  SwiftLIntRuleStudioTests
//
//  Single rule simulation tests
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

struct ImpactSimulatorSingleRuleTests {
    @Test("ImpactSimulator simulates rule with zero violations")
    func testSimulateRuleZeroViolations() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        _ = try ImpactSimulatorTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let x = 1\n"
        )

        let workspace = await MainActor.run { Workspace(path: tempDir) }
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLI(violations: [])

        let result = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "test_rule",
                workspace: workspace,
                baseConfigPath: nil
            )
        }

        let (ruleId, violationCount, isSafe, hasViolations, affectedFiles) = await MainActor.run {
            (result.ruleId, result.violationCount, result.isSafe, result.hasViolations, result.affectedFiles)
        }

        #expect(ruleId == "test_rule")
        #expect(violationCount == 0)
        #expect(isSafe == true)
        #expect(hasViolations == false)
        #expect(affectedFiles.isEmpty)
    }

    @Test("ImpactSimulator simulates rule with violations")
    func testSimulateRuleWithViolations() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        _ = try ImpactSimulatorTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let x = 1\n"
        )

        let violations = [
            Violation(
                ruleID: "test_rule",
                filePath: "Test.swift",
                line: 1,
                column: 1,
                severity: .warning,
                message: "Test violation"
            )
        ]

        let workspace = await MainActor.run { Workspace(path: tempDir) }
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLI(violations: violations)

        let result = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "test_rule",
                workspace: workspace,
                baseConfigPath: nil
            )
        }

        let (ruleId, violationCount, isSafe, hasViolations, affectedFiles) = await MainActor.run {
            (result.ruleId, result.violationCount, result.isSafe, result.hasViolations, result.affectedFiles)
        }

        #expect(ruleId == "test_rule")
        #expect(violationCount == 1)
        #expect(isSafe == false)
        #expect(hasViolations == true)
        #expect(affectedFiles.count == 1)
    }

    @Test("ImpactSimulator filters violations by rule ID")
    func testFilterViolationsByRuleID() async throws {
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

        let result = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "rule1",
                workspace: workspace,
                baseConfigPath: nil
            )
        }

        let snapshot = await MainActor.run {
            (result.ruleId, result.violations.count)
        }
        #expect(snapshot.0 == "rule1")
        #expect(snapshot.1 == 1)
    }
}
