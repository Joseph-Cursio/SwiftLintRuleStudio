//
//  SwiftLintDeprecations.swift
//  SwiftLintRuleStudio
//
//  Static database of SwiftLint rule deprecations, renames, and removals across versions
//

import Foundation

public struct DeprecationEntry: Sendable {
    public let deprecatedInVersion: String
    public let replacement: String?
    public let message: String

    public init(
        deprecatedInVersion: String,
        replacement: String?,
        message: String
    ) {
        self.deprecatedInVersion = deprecatedInVersion
        self.replacement = replacement
        self.message = message
    }
}

public struct RemovalEntry: Sendable {
    public let removedInVersion: String
    public let replacement: String?
    public let message: String

    public init(
        removedInVersion: String,
        replacement: String?,
        message: String
    ) {
        self.removedInVersion = removedInVersion
        self.replacement = replacement
        self.message = message
    }
}

/// Static database of SwiftLint rule deprecations, renames, and removals
public enum SwiftLintDeprecations {

    // MARK: - Renamed Rules (old identifier -> new identifier)

    /// Map of old rule identifiers to their renamed replacements
    public static let renamedRules: [String: String] = [
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
        // 0.60.0
        "redundant_optional_initialization": "implicit_optional_initialization",
        // 0.61.0
        "operator_whitespace": "function_name_whitespace",
        // 0.63.0
        "redundant_self_in_closure": "redundant_self"
    ]

    // MARK: - Deprecated Rules (still work but will be removed)

    /// Map of deprecated rule identifiers to their deprecation details
    public static let deprecatedRules: [String: DeprecationEntry] = [
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
        "redundant_optional_initialization": DeprecationEntry(
            deprecatedInVersion: "0.60.0",
            replacement: "implicit_optional_initialization",
            message: "Use 'implicit_optional_initialization' (style: always mimics the old behavior)."
        ),
        "operator_whitespace": DeprecationEntry(
            deprecatedInVersion: "0.61.0",
            replacement: "function_name_whitespace",
            message: "Merged into 'function_name_whitespace'. The old identifier still resolves via alias."
        ),
        "redundant_self_in_closure": DeprecationEntry(
            deprecatedInVersion: "0.63.0",
            replacement: "redundant_self",
            message: "Renamed to 'redundant_self' (broader scope). Kept as a deprecated alias."
        )
    ]

    // MARK: - Removed Rules (no longer recognized by SwiftLint)

    /// Map of removed rule identifiers to their removal details
    public static let removedRules: [String: RemovalEntry] = [
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
        "anyobject_protocol": RemovalEntry(
            removedInVersion: "0.57.0",
            replacement: nil,
            message: "This rule was removed with no functional replacement."
        ),
        "inert_defer": RemovalEntry(
            removedInVersion: "0.58.0",
            replacement: "no_empty_block",
            message: "Removed after being deprecated. Use 'no_empty_block' instead."
        ),
        "unused_capture_list": RemovalEntry(
            removedInVersion: "0.58.0",
            replacement: "unused_closure_use",
            message: "Removed after being deprecated. Use 'unused_closure_use' instead."
        )
    ]

    // MARK: - Version Rule Additions (version -> new rules added)

    /// Map of SwiftLint versions to rules introduced in that version
    public static let versionRuleAdditions: [String: [String]] = [
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
        // Additions 0.56.0–0.63.3, verified against the realm/SwiftLint CHANGELOG (2026-07-07).
        // Not listed: `no_empty_block` (changelog places it here but it is already tracked at
        // 0.46.0), and `opaque_over_existential` (added in 0.59.0, removed again in 0.59.1 — it
        // does not exist in 0.65.0). Versions 0.64.0, 0.64.1, and 0.65.0 added no new rules.
        "0.56.0": ["attribute_name_spacing", "contrasted_opening_brace", "prefer_key_path", "unused_parameter"],
        "0.57.0": ["optional_data_string_conversion"],
        "0.58.0": ["async_without_await", "redundant_sendable"],
        "0.60.0": ["implicit_optional_initialization", "prefer_condition_list"],
        "0.61.0": ["function_name_whitespace"],
        "0.62.0": ["prefer_asset_symbols"],
        "0.62.2": ["incompatible_concurrency_annotation"],
        "0.63.0": ["multiline_call_arguments", "unneeded_escaping", "unneeded_throws_rethrows"],
        "0.63.3": [
            "discouraged_default_parameter",
            "invisible_character",
            "legacy_uigraphics_function",
            "redundant_final",
            "variable_shadowing"
        ]
    ]

    // MARK: - Helpers

    /// Compare two semantic version strings. Returns true if lhs < rhs.
    public static func isVersion(_ lhs: String, lessThan rhs: String) -> Bool {
        let parts1 = lhs.split(separator: ".").compactMap { Int($0) }
        let parts2 = rhs.split(separator: ".").compactMap { Int($0) }

        for idx in 0..<max(parts1.count, parts2.count) {
            let val1 = idx < parts1.count ? parts1[idx] : 0
            let val2 = idx < parts2.count ? parts2[idx] : 0
            if val1 < val2 { return true }
            if val1 > val2 { return false }
        }
        return false
    }

    /// Get all rules added between two versions (exclusive of fromVersion, inclusive of toVersion)
    public static func rulesAdded(from fromVersion: String, to toVersion: String) -> [String] {
        var result: [String] = []
        for (version, rules) in versionRuleAdditions {
            if isVersion(fromVersion, lessThan: version) && !isVersion(toVersion, lessThan: version) {
                result.append(contentsOf: rules)
            }
        }
        return result.sorted()
    }
}
