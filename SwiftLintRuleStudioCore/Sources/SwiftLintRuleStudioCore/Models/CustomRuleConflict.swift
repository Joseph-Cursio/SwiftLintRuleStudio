//
//  CustomRuleConflict.swift
//  SwiftLintRuleStudio
//
//  A custom rule whose identifier collides with a built-in SwiftLint rule.
//  SwiftLint allows this silently: both rules run and report under the same
//  identifier, so their violations are indistinguishable and can't be enabled,
//  disabled, or configured separately. This advisory surfaces that.
//

import Foundation

/// An advisory that a `custom_rules` entry shares its name with a built-in rule.
public struct CustomRuleConflict: Identifiable, Sendable {
    /// The colliding identifier (shared by the custom rule and a built-in rule).
    nonisolated public let ruleIdentifier: String

    nonisolated public var id: String { ruleIdentifier }

    nonisolated public init(ruleIdentifier: String) {
        self.ruleIdentifier = ruleIdentifier
    }

    /// A soft, user-facing advisory message.
    nonisolated public var message: String {
        "Custom rule '\(ruleIdentifier)' shares its name with a built-in SwiftLint rule. "
            + "Both run under the same identifier, so their violations are hard to tell apart "
            + "and can't be enabled, disabled, or configured separately — consider renaming it "
            + "to distinguish from the built-in rule of the same name."
    }
}
