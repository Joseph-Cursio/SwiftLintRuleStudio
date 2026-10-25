//
//  YAMLConfigDiffUnmodeledRulesTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Rule keys the engine keeps only as passthrough nodes: a diff counts their
//  changes, and SwiftLint's own top-level options are not taken for rules.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct YAMLConfigDiffUnmodeledRulesTests {

    private static func diff(_ before: String, _ after: String) throws -> YAMLConfigurationEngine.ConfigDiff {
        YAMLConfigurationEngine.diff(
            from: try YAMLConfigurationEngine.parse(before),
            to: try YAMLConfigurationEngine.parse(after)
        )
    }

    /// `rule: error` is a severity shorthand the engine does not model. The Migration Assistant
    /// renames and removes such rules, and offers Apply only for a diff with changes.
    @Test("Renaming, removing or changing a severity-shorthand rule is a change", arguments: [
        ("redundant_self_in_closure: error\n", "redundant_self: error\n"),
        ("inert_defer: warning\nline_length: 120\n", "line_length: 120\n"),
        ("redundant_self: error\n", "redundant_self: warning\n")
    ])
    func severityShorthandChanges(before: String, after: String) throws {
        #expect(try Self.diff(before, after).hasChanges)
    }

    @Test("Identical configurations report no changes")
    func identicalHasNoChanges() throws {
        let yaml = "redundant_self: error\nopt_in_rules:\n  - empty_count\n"
            + "custom_rules:\n  todo_ticket:\n    regex: x\n"
        #expect(try Self.diff(yaml, yaml).hasChanges == false)
    }

    /// SwiftLint reads these as options: `enabled_rules` is the deprecated spelling of
    /// `opt_in_rules`, and `indentation` sets the indentation width.
    @Test("enabled_rules, indentation and other options are not rules", arguments: [
        ("enabled_rules", "enabled_rules:\n  - empty_count\n"),
        ("indentation", "indentation: 4\n"),
        ("warning_threshold", "warning_threshold: 3\n"),
        ("custom_rules", "custom_rules:\n  todo_ticket:\n    regex: x\n")
    ])
    func optionsAreNotRules(key: String, yaml: String) throws {
        let config = try YAMLConfigurationEngine.parse(yaml)
        #expect(config.rules[key] == nil)
        #expect(config.ruleIdsAsWritten.contains(key) == false)
    }
}
