//
//  RuleAuditModel.swift
//  SwiftLintRuleStudio
//

import Foundation
import Observation

/// What the rule audit shows and is doing: its entries, the selection and the expanded row,
/// a run's progress, and an error to report. `RuleAuditView` owns one and hands it to
/// `RuleAuditContent`.
@MainActor
@Observable
final class RuleAuditModel {
    var isAuditing = false
    var auditProgress: AuditProgress?
    var auditEntries: [RuleAuditEntry]
    var selectedRules: Set<String>
    var expandedRuleId: String?
    var totalSwiftFiles: Int
    var auditDuration: TimeInterval
    var isEnabling = false
    var showError = false
    var errorMessage: String?
    /// Runs the audit, so a new run, a workspace change or leaving the view can cancel it.
    let auditRunner = RuleAuditRunner()

    init(
        auditEntries: [RuleAuditEntry] = [],
        selectedRules: Set<String> = [],
        totalSwiftFiles: Int = 0,
        auditDuration: TimeInterval = 0
    ) {
        self.auditEntries = auditEntries
        self.selectedRules = selectedRules
        self.totalSwiftFiles = totalSwiftFiles
        self.auditDuration = auditDuration
    }
}
