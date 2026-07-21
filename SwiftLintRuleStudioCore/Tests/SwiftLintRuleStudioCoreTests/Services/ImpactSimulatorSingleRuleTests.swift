//
//  ImpactSimulatorSingleRuleTests.swift
//  SwiftLintRuleStudioTests
//
//  Single rule simulation tests
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

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
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLIActor(violations: [])

        let result = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "test_rule",
                workspace: workspace,
                baseConfigPath: nil
            )
        }

        #expect(result.ruleId == "test_rule")
        #expect(result.violationCount == 0)
        #expect(result.isSafe)
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
                severity: .warning,
                message: "Test violation"
            ,
                column: 1)
        ]

        let workspace = Workspace(path: tempDir)
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLIActor(violations: violations)

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
        #expect(result.hasViolations)
        #expect(result.affectedFiles.count == 1)
    }

    // Regression for P2.1: the parser read item["column"], but SwiftLint's JSON
    // reporter names the column "character" (as WorkspaceAnalyzer already does), so
    // every simulated violation's column was silently 0.
    @Test("Simulated violation column comes from SwiftLint's character field")
    func testSimulatedViolationPreservesColumn() async throws {
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
                line: 12,
                severity: .warning,
                message: "col test",
                column: 42
            )
        ]

        let workspace = Workspace(path: tempDir)
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLIActor(violations: violations)

        let result = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "test_rule",
                workspace: workspace,
                baseConfigPath: nil
            )
        }

        let violation = try #require(result.violations.first)
        #expect(violation.column == 42, "column must come from the `character` field, not default to 0")
        #expect(violation.line == 12)
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
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLIActor(violations: violations)

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
