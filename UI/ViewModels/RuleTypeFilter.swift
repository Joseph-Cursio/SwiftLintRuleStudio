//
//  RuleTypeFilter.swift
//  SwiftLintRuleStudio
//

import SwiftLintRuleStudioCore

/// Filter on how SwiftLint treats a rule out of the box, regardless of this
/// workspace's configuration.
enum RuleTypeFilter: String, CaseIterable, Identifiable {
    case all
    /// Runs unless a configuration disables it.
    case onByDefault
    /// Runs only when a configuration enables it.
    case optIn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .onByDefault: return "Default"
        case .optIn: return "Opt-In"
        }
    }

    func matches(_ rule: Rule) -> Bool {
        switch self {
        case .all: true
        case .onByDefault: !rule.isOptIn
        case .optIn: rule.isOptIn
        }
    }
}
