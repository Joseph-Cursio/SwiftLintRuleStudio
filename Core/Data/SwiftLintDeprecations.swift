//
//  SwiftLintDeprecations.swift
//  SwiftLintRuleStudio
//
//  Static database of SwiftLint rule deprecations, renames, and removals across versions
//

import Foundation

struct DeprecationEntry: Sendable {
    let deprecatedInVersion: String
    let replacement: String?
    let message: String
}

struct RemovalEntry: Sendable {
    let removedInVersion: String
    let replacement: String?
    let message: String
}

enum SwiftLintDeprecations {

    // MARK: - Renamed Rules (old identifier -> new identifier)

    static let renamedRules: [String: String] = [
        // 0.25.0
        "variable_name": "identifier_name",
        "variable_name_max_length": "identifier_name",
        "variable_name_min_length": "identifier_name",
        "type_name_max_length": "type_name",
        "type_name_min_length": "type_name",
        // 0.29.0
        "generic_type_name": "identifier_name",
        // 0.39.0
        "unused_capture_list": "unused_closure_use",
        // 0.46.0
        "inert_defer": "no_empty_block",
        // 0.50.0
        "multiple_closures_with_trailing_closure": "trailing_closure",
        // 0.53.0
        "cyclomatic_complexity": "function_body_length",
        // Legacy rules renamed in various versions
        "redundant_string_enum_value": "redundant_string_enum_value",
        // 0.42.0
        "unused_import": "unused_import",
        // 0.55.0
        "no_space_in_method_call": "no_space_in_method_call",
    ]

    // MARK: - Deprecated Rules (still work but will be removed)

    static let deprecatedRules: [String: DeprecationEntry] = [
        "variable_name": DeprecationEntry(
            deprecatedInVersion: "0.25.0",
            replacement: "identifier_name",
            message: "Use 'identifier_name' instead."
        ),
        "type_name_max_length": DeprecationEntry(
            deprecatedInVersion: "0.25.0",
            replacement: "type_name",
            message: "Configure max_length on 'type_name' instead."
        ),
        "type_name_min_length": DeprecationEntry(
            deprecatedInVersion: "0.25.0",
            replacement: "type_name",
            message: "Configure min_length on 'type_name' instead."
        ),
        "variable_name_max_length": DeprecationEntry(
            deprecatedInVersion: "0.25.0",
            replacement: "identifier_name",
            message: "Configure max_length on 'identifier_name' instead."
        ),
        "variable_name_min_length": DeprecationEntry(
            deprecatedInVersion: "0.25.0",
            replacement: "identifier_name",
            message: "Configure min_length on 'identifier_name' instead."
        ),
        "generic_type_name": DeprecationEntry(
            deprecatedInVersion: "0.29.0",
            replacement: "identifier_name",
            message: "This rule is now part of 'identifier_name'."
        ),
        "unused_capture_list": DeprecationEntry(
            deprecatedInVersion: "0.39.0",
            replacement: "unused_closure_use",
            message: "Use 'unused_closure_use' instead."
        ),
        "inert_defer": DeprecationEntry(
            deprecatedInVersion: "0.46.0",
            replacement: "no_empty_block",
            message: "Use 'no_empty_block' instead."
        ),
        "multiple_closures_with_trailing_closure": DeprecationEntry(
            deprecatedInVersion: "0.50.0",
            replacement: "trailing_closure",
            message: "Use 'trailing_closure' instead."
        ),
    ]

    // MARK: - Removed Rules (no longer recognized by SwiftLint)

    static let removedRules: [String: RemovalEntry] = [
        "variable_name": RemovalEntry(
            removedInVersion: "0.35.0",
            replacement: "identifier_name",
            message: "This rule was removed. Use 'identifier_name' instead."
        ),
        "variable_name_max_length": RemovalEntry(
            removedInVersion: "0.35.0",
            replacement: "identifier_name",
            message: "Configure max_length on 'identifier_name' instead."
        ),
        "variable_name_min_length": RemovalEntry(
            removedInVersion: "0.35.0",
            replacement: "identifier_name",
            message: "Configure min_length on 'identifier_name' instead."
        ),
        "type_name_max_length": RemovalEntry(
            removedInVersion: "0.35.0",
            replacement: "type_name",
            message: "Configure max_length on 'type_name' instead."
        ),
        "type_name_min_length": RemovalEntry(
            removedInVersion: "0.35.0",
            replacement: "type_name",
            message: "Configure min_length on 'type_name' instead."
        ),
    ]

    // MARK: - Version Rule Additions (version -> new rules added)

    static let versionRuleAdditions: [String: [String]] = [
        "0.25.0": ["identifier_name", "file_name_no_space"],
        "0.27.0": ["multiline_arguments", "multiline_parameters"],
        "0.29.0": ["last_where", "contains_over_first_not_nil"],
        "0.30.0": ["overridden_super_call", "prohibited_super_call"],
        "0.31.0": ["anyobject_protocol", "collection_alignment"],
        "0.33.0": ["computed_accessors_order", "reduce_boolean"],
        "0.35.0": ["no_space_in_method_call", "optional_enum_case_matching"],
        "0.38.0": ["indentation_width", "prefer_self_in_static_references"],
        "0.39.0": ["unused_closure_use", "ibinspectable_in_extension"],
        "0.42.0": ["test_case_accessibility", "balanced_xctest_lifecycle"],
        "0.43.0": ["discouraged_none_name", "invalid_swiftlint_command"],
        "0.44.0": ["non_overridable_class_declaration"],
        "0.46.0": ["no_empty_block", "comma_inheritance"],
        "0.48.0": ["direct_return", "period_spacing"],
        "0.50.0": ["sorted_enum_cases", "self_binding", "shorthand_optional_binding"],
        "0.52.0": ["superfluous_else"],
        "0.54.0": ["blanket_disable_command"],
        "0.55.0": ["one_declaration_per_file", "non_optional_string_data_conversion"],
    ]

    // MARK: - Helpers

    /// Compare two semantic version strings. Returns true if v1 < v2.
    static func isVersion(_ v1: String, lessThan v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(parts1.count, parts2.count) {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 < p2 { return true }
            if p1 > p2 { return false }
        }
        return false
    }

    /// Get all rules added between two versions (exclusive of fromVersion, inclusive of toVersion)
    static func rulesAdded(from fromVersion: String, to toVersion: String) -> [String] {
        var result: [String] = []
        for (version, rules) in versionRuleAdditions {
            if isVersion(fromVersion, lessThan: version) && !isVersion(toVersion, lessThan: version) {
                result.append(contentsOf: rules)
            }
        }
        return result.sorted()
    }
}
