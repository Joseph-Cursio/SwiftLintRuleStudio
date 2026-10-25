//
//  EffortCategory.swift
//  SwiftLintRuleStudio
//

import SwiftUI

/// How much work enabling a rule would create, judged by its simulated violation count — or,
/// for the last two cases, why the audit has no count to judge by.
enum EffortCategory: String, CaseIterable, Sendable {
    case safe
    case low
    case moderate
    case high
    /// The simulation failed, so the rule's impact is unknown.
    case failed
    /// Linting cannot measure the rule: an analyzer rule, or a SourceKit rule where SourceKit
    /// can't load.
    case unmeasurable

    /// The category for a measured violation count.
    ///
    /// A negative count is not a measurement — it was the simulator's failure signal — so it is
    /// a failure here. Left to `default` it would be `.high`; clamped to 0 first, as the audit
    /// once did, it was `.safe`.
    init(violationCount: Int) {
        switch violationCount {
        case ..<0: self = .failed
        case 0: self = .safe
        case 1...5: self = .low
        case 6...25: self = .moderate
        default: self = .high
        }
    }

    var label: String {
        switch self {
        case .safe: "Safe to enable"
        case .low: "Low effort"
        case .moderate: "Moderate effort"
        case .high: "High effort"
        case .failed: "Simulation failed"
        // Reason-neutral: an analyzer rule and a SourceKit rule can't be measured for
        // different reasons, and the row's explanation says which.
        case .unmeasurable: "Can't be measured here"
        }
    }

    var color: Color {
        switch self {
        case .safe: .green
        case .low: .yellow
        case .moderate: .orange
        case .high: .red
        case .failed: .red
        case .unmeasurable: .secondary
        }
    }

    var iconName: String {
        switch self {
        case .safe: "checkmark.circle.fill"
        case .low: "arrow.up.circle.fill"
        case .moderate: "exclamationmark.circle.fill"
        case .high: "xmark.circle.fill"
        case .failed: "exclamationmark.octagon.fill"
        case .unmeasurable: "questionmark.circle"
        }
    }
}
