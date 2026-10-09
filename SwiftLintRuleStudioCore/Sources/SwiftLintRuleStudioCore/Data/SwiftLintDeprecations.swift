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

    /// Map of old rule identifiers to their renamed replacements.
    /// Migration and Version Check offer each entry as a one-click rename, so an old identifier
    /// must no longer be a SwiftLint rule (a deprecated alias is fine) and a new one must be.
    /// A rule retired in favor of a compiler warning has no rename; it belongs in `removedRules`.
    /// `DeprecationDataTests` in SwiftLintInProcessBackend checks this against the linked SwiftLint.
    public static let renamedRules: [String: String] = [
        // 0.17.0
        "variable_name": "identifier_name",
        // 0.50.0
        "if_let_shadowing": "shorthand_optional_binding",
        // 0.60.0
        "redundant_optional_initialization": "implicit_optional_initialization",
        // 0.61.0
        "operator_whitespace": "function_name_whitespace",
        // 0.63.0
        "redundant_self_in_closure": "redundant_self"
    ]

    // MARK: - Aliases (old identifier -> current identifier)

    /// Old names SwiftLint still reads as a current rule — the rules' `deprecatedAliases` in
    /// SwiftLint 0.65. A rule listed or configured under one of these is the same rule as under
    /// its current name. ``renamedRules`` is broader: some of its entries point to a different
    /// rule that took over the job, while the old rule still exists — `generic_type_name` and
    /// `multiple_closures_with_trailing_closure` both still run on their own.
    public static let ruleAliases: [String: String] = [
        "variable_name": "identifier_name",
        "redundant_optional_initialization": "implicit_optional_initialization",
        "operator_whitespace": "function_name_whitespace",
        "redundant_self_in_closure": "redundant_self",
        "if_let_shadowing": "shorthand_optional_binding"
    ]

    // MARK: - Deprecated Rules (still work but will be removed)

    /// Map of deprecated rule identifiers to their deprecation details
    public static let deprecatedRules: [String: DeprecationEntry] = [
        "variable_name": DeprecationEntry(
            deprecatedInVersion: "0.17.0",
            replacement: "identifier_name",
            message: "Renamed to 'identifier_name'. Kept as a deprecated alias."
        ),
        "if_let_shadowing": DeprecationEntry(
            // Shipped only in 0.50.0-rc.1, then renamed before the 0.50.0 release.
            deprecatedInVersion: "0.50.0",
            replacement: "shorthand_optional_binding",
            message: "Renamed to 'shorthand_optional_binding'. Kept as a deprecated alias."
        ),
        "anyobject_protocol": DeprecationEntry(
            deprecatedInVersion: "0.50.0",
            replacement: nil,
            message: "Deprecated because the Swift compiler now handles this."
        ),
        "unused_capture_list": DeprecationEntry(
            deprecatedInVersion: "0.51.0",
            replacement: nil,
            message: "Deprecated in favor of the Swift compiler's unused capture warning."
        ),
        "inert_defer": DeprecationEntry(
            deprecatedInVersion: "0.51.0",
            replacement: nil,
            message: "Deprecated in favor of the Swift compiler's warning for a defer at the end of its scope."
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
        // Merged into `variable_name` (now `identifier_name`) as its length limits.
        "variable_name_max_length": RemovalEntry(
            removedInVersion: "0.7.0",
            replacement: "identifier_name",
            message: "Configure max_length on 'identifier_name' (named 'variable_name' before 0.17.0) instead."
        ),
        "variable_name_min_length": RemovalEntry(
            removedInVersion: "0.7.0",
            replacement: "identifier_name",
            message: "Configure min_length on 'identifier_name' (named 'variable_name' before 0.17.0) instead."
        ),
        "anyobject_protocol": RemovalEntry(
            removedInVersion: "0.57.0",
            replacement: nil,
            message: "This rule was removed with no functional replacement."
        ),
        "inert_defer": RemovalEntry(
            removedInVersion: "0.58.0",
            replacement: nil,
            message: "Removed after being deprecated. The Swift compiler warns about this instead."
        ),
        "unused_capture_list": RemovalEntry(
            removedInVersion: "0.58.0",
            replacement: nil,
            message: "Removed after being deprecated. The Swift compiler warns about this instead."
        ),
        "opaque_over_existential": RemovalEntry(
            removedInVersion: "0.59.1",
            replacement: nil,
            message: "Removed because it caused too many false positives."
        )
    ]

    // MARK: - Version Rule Additions (version -> new rules added)

    /// Map of SwiftLint versions to notable rules introduced in that version (not every rule).
    /// Each version is the first release whose source declares the rule, checked against
    /// SwiftLint's release tags (2026-10-09). The CHANGELOG is wrong about two: it lists
    /// `file_name_no_space` under 0.34.0 and `attribute_name_spacing` under 0.56.0, but they
    /// first shipped in 0.38.1 and 0.57.0. Versions 0.64.0, 0.64.1, and 0.65.0 added no new
    /// rules. A rule added and later removed, like `opaque_over_existential` (0.59.0 only),
    /// stays listed here; callers drop it with `isRemoved(_:by:)`.
    public static let versionRuleAdditions: [String: [String]] = [
        "0.13.0": ["overridden_super_call"],
        "0.14.0": ["prohibited_super_call"],
        "0.17.0": ["identifier_name"],
        "0.20.0": ["multiline_parameters"],
        "0.23.0": ["contains_over_first_not_nil", "multiline_arguments"],
        "0.27.0": ["anyobject_protocol"],
        "0.28.0": ["collection_alignment"],
        "0.29.3": ["last_where"],
        "0.32.0": ["reduce_boolean"],
        "0.35.0": ["no_space_in_method_call"],
        "0.38.1": ["file_name_no_space", "optional_enum_case_matching"],
        "0.38.2": ["indentation_width"],
        "0.40.0": ["computed_accessors_order", "ibinspectable_in_extension"],
        "0.41.0": ["test_case_accessibility"],
        "0.43.0": ["balanced_xctest_lifecycle"],
        "0.44.0": ["discouraged_none_name"],
        "0.45.1": ["prefer_self_in_static_references"],
        "0.47.1": ["comma_inheritance"],
        "0.49.1": ["self_binding"],
        "0.50.0": ["shorthand_optional_binding"],
        "0.51.0": ["blanket_disable_command", "direct_return", "invalid_swiftlint_command", "period_spacing"],
        "0.52.0": ["sorted_enum_cases", "superfluous_else"],
        "0.53.0": ["non_overridable_class_declaration"],
        "0.55.0": ["one_declaration_per_file", "non_optional_string_data_conversion"],
        "0.56.0": ["contrasted_opening_brace", "no_empty_block", "prefer_key_path", "unused_parameter"],
        "0.57.0": ["attribute_name_spacing", "optional_data_string_conversion"],
        "0.58.0": ["async_without_await", "redundant_sendable"],
        "0.59.0": ["opaque_over_existential"],
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

    /// Whether `rule` was removed at or before `version`.
    public static func isRemoved(_ rule: String, by version: String) -> Bool {
        guard let removedIn = removedRules[rule]?.removedInVersion else { return false }
        return !isVersion(version, lessThan: removedIn)
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
