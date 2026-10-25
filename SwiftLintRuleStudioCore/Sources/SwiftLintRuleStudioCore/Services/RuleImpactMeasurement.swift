//
//  RuleImpactMeasurement.swift
//  SwiftLintRuleStudio
//
//  Whether simulating a rule produced a violation count, and why not when it didn't.
//

import Foundation

/// Why linting cannot measure a rule.
nonisolated public enum UnmeasurableReason: Sendable, Hashable {
    /// An analyzer rule. SwiftLint runs these only under `swiftlint analyze`, fed the compiler
    /// arguments of a real build; `swiftlint lint` drops them before it starts, so they always lint
    /// clean. Neither backend can measure them: the CLI seam has no analyze command, and the
    /// sandboxed edition cannot run the build that would produce those arguments.
    case analyzerRule
    /// A SourceKit-backed rule in an edition that cannot load SourceKit (no
    /// `AppCapability.sourceKitRules`), where it produces no violations at all.
    case sourceKitUnavailable
}

/// Whether simulating a rule produced a violation count that can be acted on.
///
/// A count of 0 is what makes a rule "safe to enable", so a simulation that produced no count
/// must never read as one that counted nothing. Before this existed a failed simulation was a
/// count of -1, which the Rule Audit clamped to 0 — so every rule it could not measure was shown
/// as safe, and "Enable all safe rules" switched them all on.
nonisolated public enum RuleImpactMeasurement: Sendable, Hashable {
    /// SwiftLint ran the rule over the workspace, and the violation count is what it found.
    case measured
    /// The simulation threw before it had a count. `reason` describes the error, when there was
    /// one to describe.
    case failed(reason: String?)
    /// Linting cannot measure the rule here: it would report 0 whatever the code holds.
    case unmeasurable(UnmeasurableReason)
}
