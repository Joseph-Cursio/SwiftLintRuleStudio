//
//  LintStudioConformances.swift
//  SwiftLintRuleStudio
//
//  Bridge conformances connecting SwiftLintRuleStudioCore types
//  to LintStudioCore protocols for shared UI components
//

import LintStudioCore
import SwiftLintRuleStudioCore
import SwiftUI

// MARK: - Severity

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

// MARK: - File marker (satisfies file_name lint rule)

private enum LintStudioConformances {}

extension Severity: @retroactive LintSeverity {
    public var isError: Bool { self == .error }
}

extension RuleCategory: @retroactive LintCategory {}

extension Violation: @retroactive LintViolation {
    public var identifier: UUID { id }
    public var ruleIdentifier: String { ruleID }
}

extension Rule: @retroactive LintRule {
    public typealias CategoryType = RuleCategory

    public var identifier: String { id }
    public var ruleDescription: String { description }
}
