//
//  EffortCategory.swift
//  SwiftLintRuleStudio
//

import SwiftUI

/// Effort category based on violation count
enum EffortCategory: String, CaseIterable, Sendable {
    case safe
    case low
    case moderate
    case high

    init(violationCount: Int) {
        switch violationCount {
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
        }
    }

    var color: Color {
        switch self {
        case .safe: .green
        case .low: .yellow
        case .moderate: .orange
        case .high: .red
        }
    }

    var iconName: String {
        switch self {
        case .safe: "checkmark.circle.fill"
        case .low: "arrow.up.circle.fill"
        case .moderate: "exclamationmark.circle.fill"
        case .high: "xmark.circle.fill"
        }
    }
}
