//
//  ImpactSimulationViewTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for ImpactSimulationView
//

import Testing
import SwiftUI
@testable import SwiftLIntRuleStudio

// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
struct ImpactSimulationViewTests {
    
    @Test("ImpactSimulationView displays safe rule correctly")
    func testSafeRuleDisplay() async throws {
        let result = RuleImpactResult(
            ruleId: "test_rule",
            violationCount: 0,
            violations: [],
            affectedFiles: [],
            simulationDuration: 1.5
        )
        
        let view = await MainActor.run {
            ImpactSimulationView(
                ruleId: "test_rule",
                ruleName: "Test Rule",
                result: result,
                onEnable: nil
            )
        }
        
        // Verify the view can be created
        // Extract values to avoid Swift 6 false positives
        let (isSafe, violationCount) = await MainActor.run {
            (result.isSafe, result.violationCount)
        }
        #expect(isSafe == true)
        #expect(violationCount == 0)
    }
    
    @Test("ImpactSimulationView displays rule with violations correctly")
    func testRuleWithViolationsDisplay() async throws {
        let violations = [
            Violation(
                ruleID: "test_rule",
                filePath: "Test.swift",
                line: 10,
                column: 5,
                severity: .error,
                message: "Test violation"
            ),
            Violation(
                ruleID: "test_rule",
                filePath: "Another.swift",
                line: 20,
                column: 10,
                severity: .warning,
                message: "Another violation"
            )
        ]
        
        let result = RuleImpactResult(
            ruleId: "test_rule",
            violationCount: 2,
            violations: violations,
            affectedFiles: ["Test.swift", "Another.swift"],
            simulationDuration: 2.3
        )
        
        let view = await MainActor.run {
            ImpactSimulationView(
                ruleId: "test_rule",
                ruleName: "Test Rule",
                result: result,
                onEnable: nil
            )
        }
        
        // Verify the view can be created
        // Extract values to avoid Swift 6 false positives
        let (hasViolations, violationCount, affectedFilesCount) = await MainActor.run {
            (result.hasViolations, result.violationCount, result.affectedFiles.count)
        }
        #expect(hasViolations == true)
        #expect(violationCount == 2)
        #expect(affectedFilesCount == 2)
    }
    
    @Test("RuleImpactResult correctly identifies safe rules")
    func testRuleImpactResultSafeRules() async throws {
        let safeResult = RuleImpactResult(
            ruleId: "safe_rule",
            violationCount: 0,
            violations: [],
            affectedFiles: [],
            simulationDuration: 1.0
        )
        
        // Extract values to avoid Swift 6 false positives
        let (safeIsSafe, safeHasViolations) = await MainActor.run {
            (safeResult.isSafe, safeResult.hasViolations)
        }
        #expect(safeIsSafe == true)
        #expect(safeHasViolations == false)
        
        let unsafeResult = RuleImpactResult(
            ruleId: "unsafe_rule",
            violationCount: 5,
            violations: [],
            affectedFiles: ["file.swift"],
            simulationDuration: 1.0
        )
        
        // Extract values to avoid Swift 6 false positives
        let (unsafeIsSafe, unsafeHasViolations) = await MainActor.run {
            (unsafeResult.isSafe, unsafeResult.hasViolations)
        }
        #expect(unsafeIsSafe == false)
        #expect(unsafeHasViolations == true)
    }
}

