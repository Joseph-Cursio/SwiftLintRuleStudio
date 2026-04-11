//
//  RuleAuditView+Support.swift
//  SwiftLintRuleStudio
//
//  Support types for the Rule Audit view
//

import SwiftUI
import SwiftLintRuleStudioCore

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

/// A single entry in the rule audit results list
struct RuleAuditEntry: Identifiable, Sendable {
    let rule: Rule
    let impactResult: RuleImpactResult?
    let isCurrentlyEnabled: Bool

    var id: String { rule.id }

    var violationCount: Int {
        guard let result = impactResult else { return 0 }
        return max(result.violationCount, 0)
    }

    var affectedFileCount: Int {
        impactResult?.affectedFiles.count ?? 0
    }

    var effortCategory: EffortCategory {
        if isCurrentlyEnabled { return .safe }
        return EffortCategory(violationCount: violationCount)
    }

    var violations: [Violation] {
        impactResult?.violations ?? []
    }

    /// Group violations by file path, sorted by count descending
    var violationsByFile: [(file: String, count: Int)] {
        let grouped = Dictionary(grouping: violations, by: \.filePath)
        return grouped.map { (file: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
}

/// Progress state for audit execution
struct AuditProgress: Sendable {
    let current: Int
    let total: Int
    let ruleId: String
}

/// Fixed column widths shared between header and data rows
enum AuditColumnWidths {
    static let checkbox: CGFloat = 20
    static let disclosure: CGFloat = 14
    static let category: CGFloat = 85
    static let violations: CGFloat = 110
    static let autoFix: CGFloat = 65
    static let affectedFiles: CGFloat = 75
    static let status: CGFloat = 70
    static let action: CGFloat = 55
    static let spacing: CGFloat = 12
    /// Total fixed width consumed by non-flexible columns
    static let leadingFixed: CGFloat = checkbox + spacing + disclosure + spacing
}

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
