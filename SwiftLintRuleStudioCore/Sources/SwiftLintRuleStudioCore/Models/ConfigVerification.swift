//
//  ConfigVerification.swift
//  SwiftLintRuleStudio
//
//  Models for reconciling the resolved-config engine against SwiftLint itself.
//  The merge engine reimplements SwiftLint's nested semantics, which drift across
//  versions — so its claims must be checked against an actual lint of the subtree
//  ("SwiftLint as oracle", docs/nested-config-visibility.md). These types carry
//  the probes and the comparison result.
//

import Foundation

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

/// The result of verifying a folder's resolved config against SwiftLint.
public struct VerificationReport: Sendable {
    /// The folder whose resolved config was checked.
    nonisolated public let targetDirectory: URL
    /// One entry per probe that was run.
    nonisolated public let verifications: [RuleVerification]

    nonisolated public init(targetDirectory: URL, verifications: [RuleVerification]) {
        self.targetDirectory = targetDirectory
        self.verifications = verifications
    }

    /// Probes where the engine and SwiftLint agreed.
    nonisolated public var matches: [RuleVerification] {
        verifications.filter(\.isMatch)
    }

    /// Probes where the engine and SwiftLint disagreed — bugs to surface loudly.
    nonisolated public var divergences: [RuleVerification] {
        verifications.filter { !$0.isMatch }
    }

    /// Whether the engine fully agrees with SwiftLint for the probed rules.
    nonisolated public var isConsistent: Bool { divergences.isEmpty }
}

// MARK: - File marker (satisfies file_name lint rule)

private enum ConfigVerification {}
