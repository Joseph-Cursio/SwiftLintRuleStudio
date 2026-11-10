//
//  RuleProbe.swift
//  SwiftLintRuleStudio
//

/// A small Swift snippet engineered to trigger exactly one rule, used to ask
/// SwiftLint "is this rule active here?" by linting it in a folder's context.
public struct RuleProbe: Sendable {
    /// The rule this probe is designed to trigger.
    nonisolated public let ruleIdentifier: String
    /// Whether the rule is opt-in (off unless `opt_in_rules` enables it). This
    /// lets the engine's "is it active" claim be computed without the full rule
    /// catalog.
    nonisolated public let isOptIn: Bool
    /// Swift source that triggers `ruleIdentifier` under default settings.
    nonisolated public let triggeringSource: String

    nonisolated public init(ruleIdentifier: String, isOptIn: Bool, triggeringSource: String) {
        self.ruleIdentifier = ruleIdentifier
        self.isOptIn = isOptIn
        self.triggeringSource = triggeringSource
    }
}
