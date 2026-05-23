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
    let totalRulesTested: Int
    let totalSwiftFiles: Int
    let auditDuration: TimeInterval

    init(entries: [RuleAuditEntry], totalSwiftFiles: Int, auditDuration: TimeInterval) {
        let disabled = entries.filter { !$0.isCurrentlyEnabled }
        self.safeCount = disabled.filter { $0.effortCategory == .safe }.count
        self.lowCount = disabled.filter { $0.effortCategory == .low }.count
        self.moderateCount = disabled.filter { $0.effortCategory == .moderate }.count
        self.highCount = disabled.filter { $0.effortCategory == .high }.count
        self.totalRulesTested = entries.count
        self.totalSwiftFiles = totalSwiftFiles
        self.auditDuration = auditDuration
    }
}
