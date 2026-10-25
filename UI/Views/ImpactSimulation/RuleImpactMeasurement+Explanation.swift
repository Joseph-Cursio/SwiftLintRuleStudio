//
//  RuleImpactMeasurement+Explanation.swift
//  SwiftLintRuleStudio
//
//  Why a simulation has no violation count, in the user's terms. Shared by the Rule Audit
//  and the single-rule Impact Simulation sheet so the two say the same thing.
//

import SwiftLintRuleStudioCore

extension RuleImpactMeasurement {
    /// Why there is no violation count, or nil for a measurement, which needs no explaining.
    var explanation: String? {
        switch self {
        case .measured:
            nil
        case .failed(let reason):
            reason ?? "The simulation stopped before it could count this rule's violations."
        case .unmeasurable(.analyzerRule):
            // Plain text, not Markdown: a `Text` built from a String shows backticks verbatim.
            "Analyzer rules run only under swiftlint analyze, which needs the compiler arguments "
                + "of a full build. Linting skips them, so their violations can't be counted here."
        case .unmeasurable(.sourceKitUnavailable):
            "This rule depends on SourceKit, which this edition can't load, so its violations "
                + "can't be counted here."
        }
    }
}
