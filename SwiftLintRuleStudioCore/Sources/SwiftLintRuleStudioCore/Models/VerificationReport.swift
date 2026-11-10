//
//  VerificationReport.swift
//  SwiftLintRuleStudio
//

import Foundation

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
