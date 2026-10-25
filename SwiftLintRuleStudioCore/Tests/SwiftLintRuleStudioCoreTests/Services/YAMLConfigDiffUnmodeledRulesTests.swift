//
//  YAMLConfigDiffUnmodeledRulesTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  What a configuration diff counts: rule keys the engine keeps only as
//  passthrough nodes, changes no rule configuration shows, and which top-level
//  keys are SwiftLint's own options rather than rules.
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

    /// `rule: error` is a severity shorthand the engine does not model; renaming one changed no
    /// key of `rules`, so the migration preview said "No changes needed" and hid Apply.
    @Test("A severity-shorthand rule counts as a rule configuration")
    func countsSeverityShorthand() throws {
        let renamed = try Self.diff("redundant_self_in_closure: error\n", "redundant_self: error\n")
        #expect(renamed.addedRules == ["redundant_self"])
        #expect(renamed.removedRules == ["redundant_self_in_closure"])
        #expect(renamed.hasChanges)

        let removed = try Self.diff("inert_defer: warning\nline_length: 120\n", "line_length: 120\n")
        #expect(removed.removedRules == ["inert_defer"])
        #expect(removed.hasChanges)

        let changed = try Self.diff("redundant_self: error\n", "redundant_self: warning\n")
        #expect(changed.modifiedRules == ["redundant_self"])
    }

    @Test("A change no rule configuration shows still counts as a change")
    func countsListOnlyChange() throws {
        let diff = try Self.diff(
            "opt_in_rules:\n  - redundant_self_in_closure\n",
            "opt_in_rules:\n  - redundant_self\n"
        )
        #expect(diff.addedRules.isEmpty && diff.removedRules.isEmpty && diff.modifiedRules.isEmpty)
        #expect(diff.hasChanges)
    }

    @Test("Identical configurations report no changes")
    func identicalHasNoChanges() throws {
        let yaml = "redundant_self: error\nopt_in_rules:\n  - empty_count\n"
            + "custom_rules:\n  todo_ticket:\n    regex: x\n"
        #expect(try Self.diff(yaml, yaml).hasChanges == false)
    }

    /// SwiftLint reads both as options: `enabled_rules` is the deprecated spelling of
    /// `opt_in_rules`, and `indentation` sets the indentation width.
    @Test("enabled_rules, indentation and other options are not rules", arguments: [
        "enabled_rules:\n  - empty_count\n", "indentation: 4\n", "warning_threshold: 3\n",
        "custom_rules:\n  todo_ticket:\n    regex: x\n"
    ])
    func optionsAreNotRules(yaml: String) throws {
        let config = try YAMLConfigurationEngine.parse(yaml)
        #expect(config.rules.isEmpty)
        #expect(config.namedRuleIds.isEmpty)
        // Survives a save and a re-read unchanged.
        #expect(try YAMLConfigurationEngine.parse(YAMLConfigurationEngine.serialize(config)) == config)
    }
}
