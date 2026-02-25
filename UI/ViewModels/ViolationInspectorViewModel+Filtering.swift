//
//  ViolationInspectorViewModel+Filtering.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

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
            filtered = filtered.filter { $0.suppressed }
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
            let comparison: ComparisonResult

            switch sortOption {
            case .file:
                comparison = lhs.filePath.localizedCaseInsensitiveCompare(rhs.filePath)
                if comparison == .orderedSame {
                    return lhs.line < rhs.line
                }
            case .rule:
                comparison = lhs.ruleID.localizedCaseInsensitiveCompare(rhs.ruleID)
                if comparison == .orderedSame {
                    return lhs.filePath.localizedCaseInsensitiveCompare(rhs.filePath) == .orderedAscending
                }
            case .severity:
                if lhs.severity != rhs.severity {
                    return lhs.severity == .error && rhs.severity == .warning
                }
                return lhs.filePath.localizedCaseInsensitiveCompare(rhs.filePath) == .orderedAscending
            case .date:
                return lhs.detectedAt > rhs.detectedAt
            case .line:
                if lhs.filePath != rhs.filePath {
                    return lhs.filePath.localizedCaseInsensitiveCompare(rhs.filePath) == .orderedAscending
                }
                return lhs.line < rhs.line
            }

            return sortOrder == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
}
