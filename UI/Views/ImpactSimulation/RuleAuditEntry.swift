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

    /// The rule's category, asked of the entry rather than reached for through it.
    ///
    /// `RuleAuditRow` read `entry.rule.category.displayName`, which is the chain
    /// `law-of-demeter` names. The row cares which category this entry is in, not that an entry
    /// contains a rule which has one.
    var category: RuleCategory { rule.category }

    /// What the simulation could say about this rule; nil for an enabled rule, which the audit
    /// doesn't simulate. A disabled rule with no result was never measured — a failure to
    /// measure, not a clean run.
    var measurement: RuleImpactMeasurement? {
        if let impactResult { return impactResult.measurement }
        return isCurrentlyEnabled ? nil : .failed(reason: nil)
    }

    /// The violations the simulation found, or nil when there is no count: the rule wasn't
    /// simulated, the simulation failed, or linting can't measure the rule.
    ///
    /// This used to clamp a failed simulation's -1 to 0 with `max(_:_:)`, and 0 is what "Safe to
    /// enable" means, so every rule the audit couldn't measure was offered to "Enable all safe
    /// rules". A missing count has to stay missing.
    var violationCount: Int? {
        guard let impactResult, impactResult.isMeasured else { return nil }
        return impactResult.violationCount
    }

    /// The files with violations, or nil when there is no count — 0 files would read as clean.
    var affectedFileCount: Int? {
        violationCount == nil ? nil : impactResult?.affectedFiles.count
    }

    var effortCategory: EffortCategory {
        if isCurrentlyEnabled { return .safe }
        if let violationCount { return EffortCategory(violationCount: violationCount) }
        if case .unmeasurable = measurement { return .unmeasurable }
        return .failed
    }

    /// Why a disabled rule has no violation count, or nil when it has one.
    var unmeasuredExplanation: String? {
        isCurrentlyEnabled ? nil : measurement?.explanation
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

    /// Whether `lhs` comes before `rhs` when the audit is sorted by violation count.
    ///
    /// Disabled rules come before enabled ones in either direction: the audit is about what
    /// enabling would cost, and an enabled rule's count is history. Within each group, entries
    /// with no count go last in either direction. They have nothing to rank by, and ranked as
    /// 0 they sorted to the top of "low first", among the rules that are safe.
    static func isOrderedByViolations(_ lhs: Self, _ rhs: Self, ascending: Bool) -> Bool {
        if lhs.isCurrentlyEnabled != rhs.isCurrentlyEnabled {
            return !lhs.isCurrentlyEnabled
        }
        return switch (lhs.violationCount, rhs.violationCount) {
        case let (left?, right?): ascending ? left < right : left > right
        case (.some, nil): true
        case (nil, _): false
        }
    }
}
