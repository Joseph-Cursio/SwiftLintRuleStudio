//
//  ViolationInspectorViewModel+Computed.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

extension ViolationInspectorViewModel {
    var selectedViolation: Violation? {
        guard let selectedId = selectedViolationId else { return nil }
        return violations.first { $0.id == selectedId }
    }

    var violationCount: Int {
        filteredViolations.count
    }

    var errorCount: Int {
        filteredViolations.filter { $0.severity == .error }.count
    }

    var warningCount: Int {
        filteredViolations.filter { $0.severity == .warning }.count
    }

    var uniqueRules: [String] {
        Array(Set(violations.map { $0.ruleID })).sorted()
    }

    var uniqueFiles: [String] {
        Array(Set(violations.map { $0.filePath })).sorted()
    }
}
