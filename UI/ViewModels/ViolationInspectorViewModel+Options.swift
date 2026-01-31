//
//  ViolationInspectorViewModel+Options.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

enum ViolationGroupingOption: String, CaseIterable {
    case none = "None"
    case file = "File"
    case rule = "Rule"
    case severity = "Severity"
}

enum ViolationSortOption: String, CaseIterable {
    case file = "File"
    case rule = "Rule"
    case severity = "Severity"
    case date = "Date"
    case line = "Line"
}

enum ViolationSortOrder: String, CaseIterable {
    case ascending = "Ascending"
    case descending = "Descending"
}
