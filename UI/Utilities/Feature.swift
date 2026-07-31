//
//  Feature.swift
//  SwiftLintRuleStudio
//
//  The features whose readiness the UI discloses.
//

import Foundation

/// A feature whose readiness the UI discloses.
///
/// Only features that are visibly incomplete need an entry here; anything not
/// listed is simply available. When a feature ships, remove it from this enum
/// rather than switching it to `.available` — `FeatureStatusTests` enforces that.
enum Feature: String, CaseIterable {
    /// The full-window preset browser with a category sidebar and card grid.
    /// The `RulePresetPicker` menu already applies every preset, so this is a
    /// nicer way to do something that already works, not a missing capability.
    case presetBrowser

    var title: String {
        switch self {
        case .presetBrowser:
            return "Browse All Presets…"
        }
    }

    var status: FeatureStatus {
        switch self {
        case .presetBrowser:
            return .comingSoon(
                note: "The preset browser isn't ready yet. You can already apply "
                    + "any preset from this menu."
            )
        }
    }
}
