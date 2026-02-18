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

        let workspace = Workspace(path: tempDir)
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLI(violations: [])

        let result = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "test_rule",
                workspace: workspace,
                baseConfigPath: nil
            )
        }

        #expect(result.ruleId == "test_rule")
        #expect(result.violationCount == 0)
        #expect(result.isSafe == true)
        #expect(result.hasViolations == false)
        #expect(result.affectedFiles.isEmpty)
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

        let workspace = Workspace(path: tempDir)
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLI(violations: violations)

        let result = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "test_rule",
                workspace: workspace,
                baseConfigPath: nil
            )
        }

        #expect(result.ruleId == "test_rule")
        #expect(result.violationCount == 1)
        #expect(result.isSafe == false)
        #expect(result.hasViolations == true)
        #expect(result.affectedFiles.count == 1)
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

        let workspace = Workspace(path: tempDir)
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLI(violations: violations)

        let result = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "rule1",
                workspace: workspace,
                baseConfigPath: nil
            )
        }

        #expect(result.ruleId == "rule1")
        #expect(result.violations.count == 1)
    }
}
