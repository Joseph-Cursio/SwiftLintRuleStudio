//
//  RulePresets.swift
//  SwiftLintRuleStudio
//
//  Static preset definitions for commonly used rule groups
//

import Foundation

/// A preset collection of SwiftLint rules for common use cases
struct RulePreset: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let name: String
    let description: String
    let icon: String  // SF Symbol name
    let ruleIds: [String]
    let category: PresetCategory

    enum PresetCategory: String, Codable, CaseIterable, Sendable {
        case performance
        case swiftUI
        case concurrency
        case codeStyle
        case documentation

        var displayName: String {
            switch self {
            case .performance: return "Performance"
            case .swiftUI: return "SwiftUI"
            case .concurrency: return "Concurrency"
            case .codeStyle: return "Code Style"
            case .documentation: return "Documentation"
            }
        }

        var icon: String {
            switch self {
            case .performance: return "speedometer"
            case .swiftUI: return "rectangle.on.rectangle"
            case .concurrency: return "arrow.triangle.branch"
            case .codeStyle: return "text.alignleft"
            case .documentation: return "doc.text"
            }
        }
    }
}

/// Static preset definitions
enum RulePresets {
    /// Performance-focused rules for optimizing Swift code
    static let performance = RulePreset(
        id: "performance",
        name: "Performance",
        description: "Rules focused on code efficiency and performance optimization",
        icon: "speedometer",
        ruleIds: [
            "reduce_into",
            "contains_over_filter_count",
            "contains_over_filter_is_empty",
            "contains_over_first_not_nil",
            "contains_over_range_nil_comparison",
            "first_where",
            "last_where",
            "sorted_first_last",
            "empty_collection_literal",
            "empty_count",
            "empty_string",
            "flatmap_over_map_reduce",
            "reduce_boolean"
        ],
        category: .performance
    )

    /// SwiftUI-specific rules for clean declarative UI code
    static let swiftUI = RulePreset(
        id: "swiftui",
        name: "SwiftUI",
        description: "Rules for writing clean SwiftUI code with proper view modifiers",
        icon: "rectangle.on.rectangle",
        ruleIds: [
            "attributes",
            "modifier_order",
            "unused_capture_list",
            "type_body_length",
            "function_body_length",
            "closure_body_length",
            "trailing_closure",
            "multiple_closures_with_trailing_closure",
            "redundant_discardable_let"
        ],
        category: .swiftUI
    )

    /// Concurrency safety rules for Swift's async/await and actors
    static let concurrencySafety = RulePreset(
        id: "concurrency_safety",
        name: "Concurrency Safety",
        description: "Rules to ensure safe async/await usage and actor isolation",
        icon: "arrow.triangle.branch",
        ruleIds: [
            "unavailable_from_async",
            "class_delegate_protocol",
            "weak_delegate",
            "unowned_variable_capture",
            "private_over_fileprivate"
        ],
        category: .concurrency
    )

    /// Code style rules for consistent formatting
    static let codeStyle = RulePreset(
        id: "code_style",
        name: "Code Style",
        description: "Consistent formatting rules for brace placement, spacing, and structure",
        icon: "text.alignleft",
        ruleIds: [
            "opening_brace",
            "closing_brace",
            "comma",
            "colon",
            "vertical_whitespace",
            "trailing_newline",
            "trailing_whitespace",
            "leading_whitespace",
            "statement_position",
            "switch_case_alignment",
            "indentation_width",
            "operator_whitespace"
        ],
        category: .codeStyle
    )

    /// Documentation rules for maintaining code documentation
    static let documentation = RulePreset(
        id: "documentation",
        name: "Documentation",
        description: "Rules to ensure proper documentation of public APIs",
        icon: "doc.text",
        ruleIds: [
            "missing_docs",
            "orphaned_doc_comment",
            "comment_spacing",
            "todo",
            "mark"
        ],
        category: .documentation
    )

    /// All available presets
    static var allPresets: [RulePreset] {
        [
            performance,
            swiftUI,
            concurrencySafety,
            codeStyle,
            documentation
        ]
    }

    /// Get a preset by its identifier
    /// - Parameter id: The preset identifier
    /// - Returns: The preset if found, nil otherwise
    static func preset(for id: String) -> RulePreset? {
        allPresets.first { $0.id == id }
    }

    /// Get all presets in a specific category
    /// - Parameter category: The preset category to filter by
    /// - Returns: Array of presets matching the category
    static func presets(in category: RulePreset.PresetCategory) -> [RulePreset] {
        allPresets.filter { $0.category == category }
    }

    /// Get all rule IDs from a preset
    /// - Parameter presetId: The preset identifier
    /// - Returns: Array of rule IDs, empty if preset not found
    static func ruleIds(for presetId: String) -> [String] {
        preset(for: presetId)?.ruleIds ?? []
    }
}
