//
//  ViolationGroupingOption.swift
//  SwiftLintRuleStudio
//

enum ViolationGroupingOption: String, CaseIterable {
    case ungrouped = "None"
    case file = "File"
    case rule = "Rule"
    case severity = "Severity"
}
