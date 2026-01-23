//
//  ImpactSimulationViewTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for ImpactSimulationView
//

import Testing
import SwiftUI
import ViewInspector
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
        
        // Verify core text and summary content
        nonisolated(unsafe) let viewCapture = view
        let (hasRuleName, hasRuleId, hasSafeText, hasSummary, hasNoViolationsText) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            let inspector = try viewCapture.inspect()
            let hasRuleName = (try? inspector.find(text: "Test Rule")) != nil
            let hasRuleId = (try? inspector.find(text: "test_rule")) != nil
            let hasSafeText = (try? inspector.find(text: "This rule is safe to enable")) != nil
            let hasSummary = (try? inspector.find(text: "Summary")) != nil
            let hasNoViolationsText = (try? inspector.find(text: "No violations found")) != nil
            return (hasRuleName, hasRuleId, hasSafeText, hasSummary, hasNoViolationsText)
        }
        
        #expect(hasRuleName == true)
        #expect(hasRuleId == true)
        #expect(hasSafeText == true)
        #expect(hasSummary == true)
        #expect(hasNoViolationsText == false)
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
        
        // Verify violation rows render
        nonisolated(unsafe) let viewCapture = view
        let (hasViolationHeader, hasFirstFile, hasSecondFile) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            let inspector = try viewCapture.inspect()
            let hasViolationHeader = (try? inspector.find(text: "Violations")) != nil
            let hasFirstFile = (try? inspector.find(text: "Test.swift")) != nil
            let hasSecondFile = (try? inspector.find(text: "Another.swift")) != nil
            return (hasViolationHeader, hasFirstFile, hasSecondFile)
        }
        
        #expect(hasViolationHeader == true)
        #expect(hasFirstFile == true)
        #expect(hasSecondFile == true)
    }
    
    @Test("ImpactSimulationView shows empty state when violations list is empty")
    func testViolationsEmptyState() async throws {
        let result = RuleImpactResult(
            ruleId: "test_rule",
            violationCount: 1,
            violations: [],
            affectedFiles: [],
            simulationDuration: 0.8
        )
        
        let view = await MainActor.run {
            ImpactSimulationView(
                ruleId: "test_rule",
                ruleName: "Test Rule",
                result: result,
                onEnable: nil
            )
        }
        
        nonisolated(unsafe) let viewCapture = view
        let hasEmptyText = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            let inspector = try viewCapture.inspect()
            return (try? inspector.find(text: "No violations found")) != nil
        }
        
        #expect(hasEmptyText == true)
    }
    
    @Test("ImpactSimulationView shows overflow text for many violations")
    func testViolationsOverflowText() async throws {
        let violations = await UITestDataFactory.createTestViolations(count: 22)
        let result = RuleImpactResult(
            ruleId: "test_rule",
            violationCount: violations.count,
            violations: violations,
            affectedFiles: ["Test.swift"],
            simulationDuration: 1.1
        )
        
        let view = await MainActor.run {
            ImpactSimulationView(
                ruleId: "test_rule",
                ruleName: "Test Rule",
                result: result,
                onEnable: nil
            )
        }
        
        nonisolated(unsafe) let viewCapture = view
        let hasOverflowText = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            let inspector = try viewCapture.inspect()
            return (try? inspector.find(text: "... and 2 more violations")) != nil
        }
        
        #expect(hasOverflowText == true)
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
