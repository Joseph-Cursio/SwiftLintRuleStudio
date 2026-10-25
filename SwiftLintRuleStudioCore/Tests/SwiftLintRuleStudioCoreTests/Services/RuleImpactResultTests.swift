//
//  RuleImpactResultTests.swift
//  SwiftLintRuleStudioTests
//
//  A simulation result with no violation count must never read as a clean run: 0 is what
//  "safe to enable" means, and the Rule Audit enables every safe rule in one click.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct RuleImpactResultTests {

    private static func measured(_ ruleId: String, violationCount: Int) -> RuleImpactResult {
        RuleImpactResult(
            ruleId: ruleId,
            violationCount: violationCount,
            violations: [],
            affectedFiles: [],
            simulationDuration: 0.1
        )
    }

    @Test("A measured result is safe only when it counted nothing")
    func measuredResultIsSafeOnlyAtZero() {
        let clean = Self.measured("clean", violationCount: 0)
        let noisy = Self.measured("noisy", violationCount: 3)

        #expect(clean.measurement == .measured)
        #expect(clean.isSafe)
        #expect(clean.hasViolations == false)
        #expect(noisy.isSafe == false)
        #expect(noisy.hasViolations)
    }

    @Test("A negative count is a failure, never a measurement")
    func negativeCountIsAFailure() {
        // -1 was the simulator's only failure signal before `measurement` existed; a caller
        // still building one that way gets a failure, not a measurement of -1.
        let legacyFailure = Self.measured("broken", violationCount: -1)

        #expect(legacyFailure.measurement == .failed(reason: nil))
        #expect(legacyFailure.isMeasured == false)
        #expect(legacyFailure.isSafe == false)
        #expect(legacyFailure.hasViolations == false)
    }

    @Test("A failed result keeps its reason and has no count")
    func failedResultKeepsReason() {
        let result = RuleImpactResult.failed(ruleId: "broken", reason: "Invalid configuration")

        #expect(result.measurement == .failed(reason: "Invalid configuration"))
        #expect(result.violationCount == -1)
        #expect(result.isSafe == false)
        #expect(result.hasViolations == false)
    }

    @Test("An unmeasurable result is not safe and has no count")
    func unmeasurableResultIsNotSafe() {
        let result = RuleImpactResult.unmeasurable(ruleId: "unused_import", reason: .analyzerRule)

        #expect(result.measurement == .unmeasurable(.analyzerRule))
        #expect(result.violationCount == -1)
        #expect(result.isSafe == false)
        #expect(result.hasViolations == false)
    }

    @Test("A result that isn't a measurement never carries a count, whatever it was built with")
    func nonMeasurementDropsItsCount() {
        let result = RuleImpactResult(
            ruleId: "broken",
            violationCount: 0,
            violations: [],
            affectedFiles: [],
            simulationDuration: 0,
            measurement: .failed(reason: "boom")
        )

        #expect(result.violationCount == -1, "a 0 here would read as a clean run")
        #expect(result.isSafe == false)
    }

    @Test("A batch's safe rules leave out failed and unmeasurable results")
    func batchSafeRulesAreMeasuredOnly() {
        let batch = BatchSimulationResult(
            results: [
                Self.measured("clean", violationCount: 0),
                Self.measured("noisy", violationCount: 2),
                .failed(ruleId: "broken", reason: "boom"),
                .unmeasurable(ruleId: "unused_import", reason: .analyzerRule)
            ],
            totalDuration: 1,
            completedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(batch.safeRules.map(\.ruleId) == ["clean"])
        #expect(batch.rulesWithViolations.map(\.ruleId) == ["noisy"])
    }
}
