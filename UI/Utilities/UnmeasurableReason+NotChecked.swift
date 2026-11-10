//
//  UnmeasurableReason+NotChecked.swift
//  SwiftLintRuleStudio
//
//  What the rule list and rule detail say about a rule this app never checks.
//  Both views take their wording from here, so the tag and the notice can't
//  disagree about why.
//

import SwiftLintRuleStudioCore

extension UnmeasurableReason {
    /// The rule list tag's tooltip: one or two sentences.
    var notCheckedHelp: String {
        switch self {
        case .analyzerRule:
            "This is an analyzer rule, which SwiftLint runs only under swiftlint analyze, "
                + "so it isn't checked in this app. You can still add it to your configuration."
        case .sourceKitUnavailable:
            "This rule depends on SourceKit, so it isn't checked in this "
                + "app. You can still add it to your configuration."
        }
    }

    /// The rule detail's notice under the Enable toggle.
    var notCheckedNotice: String {
        switch self {
        case .analyzerRule:
            "This is an analyzer rule, so it isn't checked in this app. SwiftLint runs "
                + "analyzer rules only under swiftlint analyze, which needs the compiler "
                + "arguments of a full build. You can still add it to your configuration "
                + "and run swiftlint analyze yourself."
        case .sourceKitUnavailable:
            "This rule depends on SourceKit, so it isn't checked in this "
                + "app. You can still add it to your configuration. SwiftLint "
                + "Rule Studio, the non-sandboxed edition, checks it using the "
                + "SwiftLint on your Mac."
        }
    }
}
