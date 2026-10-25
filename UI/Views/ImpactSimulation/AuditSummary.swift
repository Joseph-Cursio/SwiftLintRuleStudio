//
//  AuditSummary.swift
//  SwiftLintRuleStudio
//

import Foundation

/// Summary counts for each effort category
struct AuditSummary: Sendable {
    let safeCount: Int
    let lowCount: Int
    let moderateCount: Int
    let highCount: Int
    /// Disabled rules whose simulation failed. Counted apart from the effort buckets, so a rule
    /// with an unknown impact is never one of the "safe" ones.
    let failedCount: Int
    /// Disabled rules linting can't measure, counted apart for the same reason.
    let unmeasurableCount: Int
    let totalRulesTested: Int
    let totalSwiftFiles: Int
    let auditDuration: TimeInterval

    init(entries: [RuleAuditEntry], totalSwiftFiles: Int, auditDuration: TimeInterval) {
        let disabled = entries.filter { !$0.isCurrentlyEnabled }
        self.safeCount = disabled.filter { $0.effortCategory == .safe }.count
        self.lowCount = disabled.filter { $0.effortCategory == .low }.count
        self.moderateCount = disabled.filter { $0.effortCategory == .moderate }.count
        self.highCount = disabled.filter { $0.effortCategory == .high }.count
        self.failedCount = disabled.filter { $0.effortCategory == .failed }.count
        self.unmeasurableCount = disabled.filter { $0.effortCategory == .unmeasurable }.count
        self.totalRulesTested = entries.count
        self.totalSwiftFiles = totalSwiftFiles
        self.auditDuration = auditDuration
    }
}
