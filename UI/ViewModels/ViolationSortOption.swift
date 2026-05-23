//
//  ViolationSortOption.swift
//  SwiftLintRuleStudio
//

import Foundation

enum ViolationSortOption: String, CaseIterable {
    case file = "File"
    case rule = "Rule"
    case severity = "Severity"
    case date = "Date"
    case line = "Line"
}
