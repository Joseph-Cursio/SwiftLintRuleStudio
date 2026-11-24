//
//  ViolationInspectorViewModel+Computed.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftLintRuleStudioCore

extension ViolationInspectorViewModel {
    var violationCount: Int {
        filteredViolations.count
    }

    var errorCount: Int {
        filteredViolations.filter { $0.severity == .error }.count
    }

    var warningCount: Int {
        filteredViolations.filter { $0.severity == .warning }.count
    }

    var suppressedCount: Int {
        filteredViolations.filter(\.suppressed).count
    }

    var uniqueRules: [String] {
        Array(Set(violations.map(\.ruleID))).sorted()
    }

    var uniqueFiles: [String] {
        Array(Set(violations.map(\.filePath))).sorted()
    }
}
