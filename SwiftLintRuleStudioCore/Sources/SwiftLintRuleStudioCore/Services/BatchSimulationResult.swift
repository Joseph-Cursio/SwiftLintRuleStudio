//
//  BatchSimulationResult.swift
//  SwiftLintRuleStudio
//
//  What simulating a batch of rules found.
//

import Foundation

/// Result of batch simulation
public struct BatchSimulationResult: Sendable {
    nonisolated public let results: [RuleImpactResult]
    nonisolated public let totalDuration: TimeInterval
    nonisolated public let completedAt: Date

    public init(results: [RuleImpactResult], totalDuration: TimeInterval, completedAt: Date) {
        self.results = results
        self.totalDuration = totalDuration
        self.completedAt = completedAt
    }

    nonisolated public var safeRules: [RuleImpactResult] {
        results.filter(\.isSafe)
    }

    nonisolated public var rulesWithViolations: [RuleImpactResult] {
        results.filter(\.hasViolations)
    }
}
