//
//  RuleImpactResult.swift
//  SwiftLintRuleStudio
//
//  What simulating one rule found — or why it found no count.
//

import Foundation

/// Result of simulating a rule's impact
public struct RuleImpactResult: Sendable, Identifiable {
    nonisolated public let ruleId: String
    nonisolated public var id: String { ruleId }
    /// The violations the rule found, or -1 whenever `measurement` is not `.measured` — so a
    /// reader that never looks at `measurement` still cannot take a missing count for a clean run.
    nonisolated public let violationCount: Int
    nonisolated public let violations: [Violation]
    nonisolated public let affectedFiles: Set<String>
    nonisolated public let simulationDuration: TimeInterval
    /// Whether `violationCount` is a measurement at all.
    nonisolated public let measurement: RuleImpactMeasurement

    public init(
        ruleId: String,
        violationCount: Int,
        violations: [Violation],
        affectedFiles: Set<String>,
        simulationDuration: TimeInterval,
        measurement: RuleImpactMeasurement = .measured
    ) {
        // A negative count was this type's only failure signal before `measurement` existed, and
        // a caller may still build a failure that way. It is a failure, never a measurement.
        let resolved: RuleImpactMeasurement = violationCount < 0 && measurement == .measured
            ? .failed(reason: nil)
            : measurement
        self.ruleId = ruleId
        self.violationCount = resolved == .measured ? violationCount : -1
        self.violations = violations
        self.affectedFiles = affectedFiles
        self.simulationDuration = simulationDuration
        self.measurement = resolved
    }

    /// The result for a rule whose simulation threw, carrying what went wrong.
    public static func failed(
        ruleId: String,
        reason: String?,
        simulationDuration: TimeInterval = 0
    ) -> Self {
        Self(
            ruleId: ruleId,
            violationCount: -1,
            violations: [],
            affectedFiles: [],
            simulationDuration: simulationDuration,
            measurement: .failed(reason: reason)
        )
    }

    /// The result for a rule linting cannot measure. Nothing was run, so nothing took any time.
    public static func unmeasurable(ruleId: String, reason: UnmeasurableReason) -> Self {
        Self(
            ruleId: ruleId,
            violationCount: -1,
            violations: [],
            affectedFiles: [],
            simulationDuration: 0,
            measurement: .unmeasurable(reason)
        )
    }

    /// Whether the simulation produced a violation count.
    nonisolated public var isMeasured: Bool {
        measurement == .measured
    }

    nonisolated public var hasViolations: Bool {
        isMeasured && violationCount > 0
    }

    /// Measured, and clean. A rule with no count is never safe: nothing showed that enabling it
    /// creates no work.
    nonisolated public var isSafe: Bool {
        isMeasured && violationCount == 0
    }
}
