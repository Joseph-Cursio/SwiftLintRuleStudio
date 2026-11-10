//
//  RuleVerification.swift
//  SwiftLintRuleStudio
//

/// The reconciliation of one rule: what the engine claims vs. what SwiftLint did.
public struct RuleVerification: Sendable {
    nonisolated public let ruleIdentifier: String
    /// Whether the resolved-config engine claims the rule is active in the folder.
    nonisolated public let engineClaimsActive: Bool
    /// Whether SwiftLint actually reported the rule when linting the probe there.
    nonisolated public let swiftLintReported: Bool

    nonisolated public init(
        ruleIdentifier: String,
        engineClaimsActive: Bool,
        swiftLintReported: Bool
    ) {
        self.ruleIdentifier = ruleIdentifier
        self.engineClaimsActive = engineClaimsActive
        self.swiftLintReported = swiftLintReported
    }

    /// Whether the engine and SwiftLint agree.
    nonisolated public var isMatch: Bool { engineClaimsActive == swiftLintReported }

    /// A loud, human-readable description of a disagreement (nil when matching).
    nonisolated public var divergenceDescription: String? {
        guard !isMatch else { return nil }
        if engineClaimsActive {
            return "\(ruleIdentifier): the inspector shows it active, but SwiftLint did not report it."
        }
        return "\(ruleIdentifier): the inspector shows it suppressed, but SwiftLint reported it."
    }
}
