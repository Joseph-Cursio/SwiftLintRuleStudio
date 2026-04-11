//
//  LintStudioConformances.swift
//  SwiftLintRuleStudio
//
//  Bridge conformances connecting SwiftLintRuleStudioCore types
//  to LintStudioCore protocols for shared UI components
//

import SwiftUI
import LintStudioCore
import SwiftLintRuleStudioCore

// MARK: - Severity

extension Severity: @retroactive LintSeverity {
    public var isError: Bool { self == .error }
}

// MARK: - RuleCategory

extension RuleCategory: @retroactive LintCategory {}

// MARK: - RuleCategory Color Mapping

enum RuleCategoryColors {
    static func color(for category: RuleCategory) -> Color {
        switch category {
        case .style: .blue
        case .lint: .red
        case .metrics: .purple
        case .performance: .orange
        case .idiomatic: .green
        }
    }
}

// MARK: - Violation

extension Violation: @retroactive LintViolation {
    public var identifier: UUID { id }
    public var ruleIdentifier: String { ruleID }
}

// MARK: - Rule

extension Rule: @retroactive LintRule {
    public typealias CategoryType = RuleCategory
    public var identifier: String { id }
    public var ruleDescription: String { description }
}
