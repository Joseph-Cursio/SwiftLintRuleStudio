//
//  RuleAuditEntry.swift
//  SwiftLintRuleStudio
//

import SwiftLintRuleStudioCore

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
