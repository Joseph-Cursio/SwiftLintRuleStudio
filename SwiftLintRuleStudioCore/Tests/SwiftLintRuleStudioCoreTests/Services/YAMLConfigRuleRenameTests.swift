//
//  YAMLConfigRuleRenameTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Tests for YAMLConfig.renameRule(_:to:), the rename the compatibility
//  report's "Fix" and the migration assistant share.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct YAMLConfigRuleRenameTests {

    @Test("Renames the rule configuration and the rule in all four lists")
    func renamesEverywhere() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules = [
            "old_rule": RuleConfiguration(enabled: true, severity: .error),
            "other_rule": RuleConfiguration(enabled: true)
        ]
        config.disabledRules = ["old_rule", "a_rule"]
        config.optInRules = ["b_rule", "old_rule"]
        config.analyzerRules = ["old_rule"]
        config.onlyRules = ["old_rule", "c_rule"]

        config.renameRule("old_rule", to: "new_rule")

        #expect(config.rules == [
            "new_rule": RuleConfiguration(enabled: true, severity: .error),
            "other_rule": RuleConfiguration(enabled: true)
        ])
        #expect(config.disabledRules == ["new_rule", "a_rule"])
        #expect(config.optInRules == ["b_rule", "new_rule"])
        #expect(config.analyzerRules == ["new_rule"])
        #expect(config.onlyRules == ["new_rule", "c_rule"])
    }

    @Test("A configuration that already names the new id keeps its entry, and no list repeats an id")
    func existingNewIdWins() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules = [
            "old_rule": RuleConfiguration(enabled: true, severity: .error),
            "new_rule": RuleConfiguration(enabled: true, severity: .warning)
        ]
        config.optInRules = ["old_rule", "a_rule", "new_rule"]
        config.onlyRules = ["old_rule", "a_rule", "old_rule"]

        config.renameRule("old_rule", to: "new_rule")

        #expect(config.rules == ["new_rule": RuleConfiguration(enabled: true, severity: .warning)])
        #expect(config.optInRules == ["a_rule", "new_rule"])
        #expect(config.onlyRules == ["new_rule", "a_rule"])
    }

    /// Renaming should leave the file as if it had been written with the new name: the rule's
    /// key in place, its comment above it, and its `key: 40` shorthand.
    @Test("A renamed rule keeps its place, its comment and its scalar shorthand")
    func renameKeepsLayout() throws {
        let written = { (ruleId: String) in
            """
            included:
              - Sources
            # Keep names short
            \(ruleId): 40
            line_length: 120
            opt_in_rules:
              - \(ruleId)
            """
        }
        var config = try YAMLConfigurationEngine.parse(written("variable_name"))
        config.renameRule("variable_name", to: "identifier_name")

        let renamed = try YAMLConfigurationEngine.serialize(config)
        let expected = try YAMLConfigurationEngine.serialize(YAMLConfigurationEngine.parse(written("identifier_name")))
        #expect(renamed == expected)
        #expect(renamed.contains("# Keep names short\nidentifier_name: 40"))
    }

    /// `rule: error` is a severity shorthand the engine does not model; it keeps the key as a
    /// passthrough node, which a rename once left behind.
    @Test("A rule configured by a severity shorthand is renamed in place")
    func renamesSeverityShorthand() throws {
        let written = { (ruleId: String) in
            """
            # Closures only
            \(ruleId): error
            line_length: 120

            """
        }
        var config = try YAMLConfigurationEngine.parse(written("redundant_self_in_closure"))
        #expect(config.rules["redundant_self_in_closure"] == nil)
        #expect(config.ruleIdsAsWritten.contains("redundant_self_in_closure"))

        config.renameRule("redundant_self_in_closure", to: "redundant_self")

        let expected = try YAMLConfigurationEngine.serialize(YAMLConfigurationEngine.parse(written("redundant_self")))
        #expect(try YAMLConfigurationEngine.serialize(config) == expected)
        #expect(config.ruleIdsAsWritten.contains("redundant_self_in_closure") == false)
    }

    @Test("A configuration for the new id wins over the old one, however each is written")
    func existingNewIdWinsOverShorthand() throws {
        var config = try YAMLConfigurationEngine.parse("""
            redundant_self_in_closure: error
            redundant_self:
              severity: warning

            """)
        config.renameRule("redundant_self_in_closure", to: "redundant_self")

        let yaml = try YAMLConfigurationEngine.serialize(config)
        #expect(yaml.contains("redundant_self_in_closure") == false)
        #expect(yaml.contains("error") == false)
        #expect(config.rules["redundant_self"]?.severity == .warning)
    }

    /// SwiftLint rejects a file that configures both an alias and its rule, so the two merge.
    @Test("Both ids configured: the old settings fill in what the new entry leaves unset")
    func mergesOldIntoNew() throws {
        var config = try YAMLConfigurationEngine.parse("""
            # Short names are fine in closures
            variable_name:
              min_length: 2
              max_length: 40
            # Long names are not
            identifier_name:
              max_length: 50

            """)
        config.renameRule("variable_name", to: "identifier_name")

        let parameters = try #require(config.rules["identifier_name"]?.parameters)
        #expect(parameters["min_length"]?.value as? Int == 2)
        #expect(parameters["max_length"]?.value as? Int == 50)
        try YAMLConfigurationEngine.validated(config)
        let yaml = try YAMLConfigurationEngine.serialize(config)
        #expect(yaml.components(separatedBy: "identifier_name:").count == 2)
        #expect(yaml.contains("variable_name") == false)
        #expect(yaml.contains("# Long names are not\n# Short names are fine in closures\nidentifier_name:"))
    }

    @Test("Both ids configured: an old severity shorthand becomes the merged entry's severity")
    func mergesOldShorthandIntoNew() throws {
        var config = try YAMLConfigurationEngine.parse("""
            variable_name: error
            identifier_name:
              min_length: 3

            """)
        config.renameRule("variable_name", to: "identifier_name")

        let merged = try #require(config.rules["identifier_name"])
        #expect(merged.severity == .error)
        #expect(merged.parameters?["min_length"]?.value as? Int == 3)
        try YAMLConfigurationEngine.validated(config)
        let yaml = try YAMLConfigurationEngine.serialize(config)
        #expect(yaml.components(separatedBy: "identifier_name:").count == 2)
        #expect(yaml.contains("variable_name") == false)
    }

    @Test("Both ids configured: a new severity shorthand is laid over the old mapping")
    func mergesNewShorthandOverOldMapping() throws {
        var config = try YAMLConfigurationEngine.parse("""
            redundant_self_in_closure:
              severity: error
              only_in_closures: false
            redundant_self: warning

            """)
        config.renameRule("redundant_self_in_closure", to: "redundant_self")

        let merged = try #require(config.rules["redundant_self"])
        #expect(merged.severity == .warning)
        #expect(merged.parameters?["only_in_closures"]?.value as? Bool == false)
        #expect(config.ruleIdsAsWritten == ["redundant_self"])
        let yaml = try YAMLConfigurationEngine.serialize(config)
        #expect(yaml.components(separatedBy: "redundant_self:").count == 2)
    }

    @Test("Both ids configured: an old comment is dropped when none of its settings survive")
    func dropsCommentOfDiscardedSettings() throws {
        var config = try YAMLConfigurationEngine.parse("""
            # Old: errors
            redundant_self_in_closure:
              severity: error
            # New: warnings
            redundant_self:
              severity: warning

            """)
        config.renameRule("redundant_self_in_closure", to: "redundant_self")

        let yaml = try YAMLConfigurationEngine.serialize(config)
        #expect(yaml.contains("# New: warnings\nredundant_self:"))
        #expect(yaml.contains("# Old: errors") == false)
        #expect(config.comments["redundant_self_in_closure"] == nil)
    }

    @Test("Renaming a rule the configuration does not name, or renaming to itself, changes nothing")
    func noOps() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules = ["a_rule": RuleConfiguration(enabled: true)]
        config.optInRules = ["a_rule"]
        let before = config

        config.renameRule("absent_rule", to: "new_rule")
        #expect(config == before)
        config.renameRule("a_rule", to: "a_rule")
        #expect(config == before)
    }
}
