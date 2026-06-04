//
//  CustomRuleConflictDetector.swift
//  SwiftLintRuleStudio
//
//  Detects `custom_rules` entries whose identifier collides with a built-in
//  SwiftLint rule. SwiftLint emits no warning for this, so the app surfaces it.
//

import Foundation
import Yams

/// Finds custom rules that shadow a built-in rule of the same name.
public struct CustomRuleConflictDetector {
    /// Creates a detector.
    nonisolated public init() {}

    /// The custom rules whose identifier also names a built-in rule.
    ///
    /// - Parameters:
    ///   - customRuleIdentifiers: names defined under the config's `custom_rules`.
    ///   - builtInRuleIdentifiers: the SwiftLint built-in rule catalog (e.g. from
    ///     ``RuleRegistry``).
    nonisolated public func conflicts(
        customRuleIdentifiers: Set<String>,
        builtInRuleIdentifiers: Set<String>
    ) -> [CustomRuleConflict] {
        customRuleIdentifiers
            .intersection(builtInRuleIdentifiers)
            .sorted()
            .map(CustomRuleConflict.init(ruleIdentifier:))
    }

    /// The custom-rule identifiers declared in a parsed config — the keys of its
    /// `custom_rules` mapping (preserved as a passthrough node, since the engine
    /// doesn't model custom rules).
    public func customRuleIdentifiers(in config: YAMLConfig) -> Set<String> {
        guard let node = config.passthroughNodes["custom_rules"],
              case .mapping(let mapping) = node else {
            return []
        }
        var identifiers: Set<String> = []
        for (keyNode, _) in mapping {
            if let key = keyNode.string {
                identifiers.insert(key)
            }
        }
        return identifiers
    }

    /// Convenience: conflicts for a parsed config against a built-in catalog.
    public func conflicts(
        in config: YAMLConfig,
        builtInRuleIdentifiers: Set<String>
    ) -> [CustomRuleConflict] {
        conflicts(
            customRuleIdentifiers: customRuleIdentifiers(in: config),
            builtInRuleIdentifiers: builtInRuleIdentifiers
        )
    }
}
