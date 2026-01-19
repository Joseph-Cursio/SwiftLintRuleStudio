//
//  SafeRulesDiscoveryViewTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for SafeRulesDiscoveryView
//

import Testing
import SwiftUI
@testable import SwiftLIntRuleStudio

// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
struct SafeRulesDiscoveryViewTests {
    
    // Workaround type to bypass Sendable check for SwiftUI views
    struct ViewResult: @unchecked Sendable {
        let view: AnyView
        let container: DependencyContainer
        
        init(view: some View, container: DependencyContainer) {
            self.view = AnyView(view)
            self.container = container
        }
    }
    
    // Workaround for Swift 6 strict concurrency: Return ViewResult instead of tuple with 'some View'
    @MainActor
    private func createSafeRulesDiscoveryView() -> ViewResult {
        let container = DependencyContainer.createForTesting()
        let view = SafeRulesDiscoveryView()
            .environmentObject(container)
        return ViewResult(view: view, container: container)
    }
    
    @Test("SafeRulesDiscoveryView initializes correctly")
    func testInitialization() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createSafeRulesDiscoveryView() }.value
        let view = result.view
        let container = result.container
        
        // Verify view can be created
        let hasImpactSimulator = await MainActor.run {
            container.impactSimulator != nil
        }
        #expect(hasImpactSimulator == true)
    }
    
    @Test("BatchSimulationResult correctly categorizes rules")
    func testBatchSimulationResultCategorization() async throws {
        let results = [
            RuleImpactResult(
                ruleId: "safe_rule_1",
                violationCount: 0,
                violations: [],
                affectedFiles: [],
                simulationDuration: 1.0
            ),
            RuleImpactResult(
                ruleId: "safe_rule_2",
                violationCount: 0,
                violations: [],
                affectedFiles: [],
                simulationDuration: 1.0
            ),
            RuleImpactResult(
                ruleId: "unsafe_rule",
                violationCount: 5,
                violations: [],
                affectedFiles: ["file.swift"],
                simulationDuration: 1.0
            )
        ]
        
        let batchResult = BatchSimulationResult(
            results: results,
            totalDuration: 3.0,
            completedAt: Date()
        )
        
        // Extract values to avoid Swift 6 false positives
        // BatchSimulationResult is a struct (Sendable), but Swift 6 has false positives
        let (safeRulesCount, violationsCount, allSafe, allHaveViolations) = await MainActor.run {
            let safeRules = batchResult.safeRules
            let rulesWithViolations = batchResult.rulesWithViolations
            return (
                safeRules.count,
                rulesWithViolations.count,
                safeRules.allSatisfy { $0.isSafe },
                rulesWithViolations.allSatisfy { $0.hasViolations }
            )
        }
        #expect(safeRulesCount == 2)
        #expect(violationsCount == 1)
        #expect(allSafe == true)
        #expect(allHaveViolations == true)
    }
    
    @Test("BatchSimulationResult handles empty results")
    func testBatchSimulationResultEmpty() async throws {
        let batchResult = BatchSimulationResult(
            results: [],
            totalDuration: 0.0,
            completedAt: Date()
        )
        
        // Extract values to avoid Swift 6 false positives
        // BatchSimulationResult is a struct (Sendable), but Swift 6 has false positives
        let (safeRulesEmpty, violationsEmpty) = await MainActor.run {
            (batchResult.safeRules.isEmpty, batchResult.rulesWithViolations.isEmpty)
        }
        #expect(safeRulesEmpty == true)
        #expect(violationsEmpty == true)
    }
}

