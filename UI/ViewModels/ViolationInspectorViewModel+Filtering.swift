//
//  ViolationInspectorViewModel+Filtering.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import SwiftLintRuleStudioCore

extension ViolationInspectorViewModel {
    func clearFilters() {
        searchText = ""
        selectedRuleIDs.removeAll()
        selectedSeverities.removeAll()
        selectedFiles.removeAll()
        showSuppressedOnly = false
    }
}

extension ViolationInspectorViewModel {
    func updateFilteredViolations() {
        guard isInitialized else { return }

        var filtered = violations

        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            filtered = filtered.filter { violation in
                violation.ruleID.lowercased().contains(searchLower) ||
                    violation.message.lowercased().contains(searchLower) ||
                    violation.filePath.lowercased().contains(searchLower)
            }
        }

        if !selectedRuleIDs.isEmpty {
            filtered = filtered.filter { selectedRuleIDs.contains($0.ruleID) }
        }

        if !selectedSeverities.isEmpty {
            filtered = filtered.filter { selectedSeverities.contains($0.severity) }
        }

        if !selectedFiles.isEmpty {
            filtered = filtered.filter { selectedFiles.contains($0.filePath) }
        }

        if showSuppressedOnly {
            filtered = filtered.filter(\.suppressed)
        }

        filtered = sortViolations(filtered)
        if !tableSortOrder.isEmpty {
            filtered.sort(using: tableSortOrder)
        }
        filteredViolations = filtered
        updateSelectionForFilteredViolations(filtered)
    }

    func sortFilteredViolations() {
        guard !tableSortOrder.isEmpty else { return }
        filteredViolations.sort(using: tableSortOrder)
    }

    func sortViolations(_ violations: [Violation]) -> [Violation] {
        violations.sorted { lhs, rhs in
            let comparison = orderedComparison(lhs, rhs)
            return sortOrder == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    /// The full ordering for the current `sortOption` as a single `ComparisonResult`
    /// (primary key, then a file/line tiebreak). `sortViolations` flips it for a
    /// descending sort, so every option honors the direction toggle uniformly.
    private func orderedComparison(_ lhs: Violation, _ rhs: Violation) -> ComparisonResult {
        let fileOrder = { lhs.filePath.localizedCaseInsensitiveCompare(rhs.filePath) }
        switch sortOption {
        case .file:
            let primary = fileOrder()
            return primary == .orderedSame ? Self.compare(lhs.line, rhs.line) : primary
        case .rule:
            let primary = lhs.ruleID.localizedCaseInsensitiveCompare(rhs.ruleID)
            return primary == .orderedSame ? fileOrder() : primary
        case .severity:
            // Errors (rank 0) order ahead of warnings (rank 1) when ascending.
            let primary = Self.compare(Self.severityRank(lhs.severity), Self.severityRank(rhs.severity))
            return primary == .orderedSame ? fileOrder() : primary
        case .date:
            // Ascending shows newest first (compare with operands swapped).
            let primary = Self.compare(rhs.detectedAt, lhs.detectedAt)
            return primary == .orderedSame ? fileOrder() : primary
        case .line:
            let primary = fileOrder()
            return primary == .orderedSame ? Self.compare(lhs.line, rhs.line) : primary
        }
    }

    /// `ComparisonResult` for two `Comparable` values (ascending sense).
    private static func compare<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    /// Sort rank for severity: errors (0) order ahead of warnings (1) when ascending.
    private static func severityRank(_ severity: Severity) -> Int {
        switch severity {
        case .error: return 0
        case .warning: return 1
        }
    }
}
