//
//  AuditProgress.swift
//  SwiftLintRuleStudio
//

/// Progress state for audit execution
struct AuditProgress: Sendable {
    let current: Int
    let total: Int
    let ruleId: String
}
