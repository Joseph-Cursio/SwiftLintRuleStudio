//
//  FeatureStatus.swift
//  SwiftLintRuleStudio
//
//  Whether a feature is finished or still to come, so the UI can say so
//  plainly instead of hiding or half-wiring it.
//

import Foundation

/// How ready a feature is.
///
/// This is a roadmap distinction and is deliberately **not** modelled as an
/// `AppCapability`. A capability describes what an edition is physically able to
/// do — the sandbox blocking `xed`, SourceKit being unloadable — and feeds
/// correctness decisions such as `Rule.isUnavailableForLinting(capabilities:)`.
/// Folding "we haven't built it yet" into that would let a roadmap choice change
/// how the app reports lint results.
enum FeatureStatus: Equatable {
    /// Finished and usable.
    case available

    /// Not finished. `note` explains what the user can do in the meantime, and
    /// is shown as the tooltip on the disclosure.
    case comingSoon(note: String)

    var isAvailable: Bool {
        self == .available
    }

    /// Short text shown next to the feature's entry point. Nil when available,
    /// because a finished feature needs no disclosure.
    var disclosure: String? {
        switch self {
        case .available:
            return nil
        case .comingSoon:
            return "Coming in a later release"
        }
    }

    /// The longer explanation, shown as a tooltip.
    var note: String? {
        switch self {
        case .available:
            return nil
        case let .comingSoon(note):
            return note
        }
    }
}
