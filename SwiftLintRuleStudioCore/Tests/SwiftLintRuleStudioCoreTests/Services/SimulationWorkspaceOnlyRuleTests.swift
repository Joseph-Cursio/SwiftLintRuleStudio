//
//  SimulationWorkspaceOnlyRuleTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Which rules a simulation lints alone (`--only-rule`), and which need every rule the configs
//  enable to be counted as Enable will find them.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct SimulationWorkspaceOnlyRuleTests {

    // MARK: - Helpers

    private func makeTempFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowOnlyRuleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// A mirror of a workspace holding `configs`, keyed by path relative to the workspace.
    private func makeShadow(_ configs: [String: String]) throws -> (SimulationWorkspace, URL) {
        let workspace = try makeTempFolder()
        for (path, content) in configs {
            try write(content, to: workspace.appendingPathComponent(path))
        }
        try write("let a = 1\n", to: workspace.appendingPathComponent("Sub/A.swift"))
        let shadow = try SimulationWorkspaceBuilder()
            .makeWorkspace(for: Workspace(path: workspace), baseConfigPath: nil)
        return (shadow, workspace)
    }

    // MARK: - Tests

    @Test("a rule is linted alone, whatever the root config lists")
    func plainRuleRunsAlone() throws {
        let (shadow, workspace) = try makeShadow([
            ".swiftlint.yml": "only_rules:\n  - line_length\n",
            "Sub/.swiftlint.yml": "disabled_rules:\n  - force_cast\n"
        ])
        defer { shadow.cleanup(); try? FileManager.default.removeItem(at: workspace) }

        #expect(shadow.onlyRule(for: "force_cast") == "force_cast")
        #expect(shadow.onlyRule(for: "empty_count") == "empty_count")
    }

    @Test("superfluous_disable_command is linted with every rule, which it reports on")
    func superfluousDisableCommandNeedsEveryRule() throws {
        let (shadow, workspace) = try makeShadow([
            ".swiftlint.yml": "disabled_rules:\n  - superfluous_disable_command\n"
        ])
        defer { shadow.cleanup(); try? FileManager.default.removeItem(at: workspace) }

        #expect(shadow.onlyRule(for: "superfluous_disable_command") == nil)
    }

    @Test("custom_rules and each custom rule are linted with every rule")
    func customRulesNeedEveryRule() throws {
        let (shadow, workspace) = try makeShadow([
            ".swiftlint.yml": "custom_rules:\n  no_number:\n    regex: NSNumber\n",
            "Sub/.swiftlint.yml": "custom_rules:\n  no_print:\n    regex: print\n"
        ])
        defer { shadow.cleanup(); try? FileManager.default.removeItem(at: workspace) }

        #expect(shadow.onlyRule(for: "custom_rules") == nil)
        #expect(shadow.onlyRule(for: "no_number") == nil)
        #expect(shadow.onlyRule(for: "no_print") == nil)
        #expect(shadow.onlyRule(for: "force_cast") == "force_cast")
    }

    @Test("a nested only_rules that leaves the rule out is written as disabling it, for a lint of it alone")
    func nestedOnlyRulesWithoutTheRule() throws {
        let (shadow, workspace) = try makeShadow([
            ".swiftlint.yml": "disabled_rules:\n  - force_cast\n",
            "Sub/.swiftlint.yml": "only_rules:\n  - line_length\nexcluded:\n  - Generated\n"
        ])
        defer { shadow.cleanup(); try? FileManager.default.removeItem(at: workspace) }
        let nested = {
            try YAMLConfigurationEngine.loadConfig(at: shadow.root.appendingPathComponent("Sub/.swiftlint.yml"))
        }

        // `--only-rule` would run force_cast in Sub/, where the nested only_rules keeps it off;
        // it honours a nested disabled_rules.
        #expect(shadow.onlyRule(for: "force_cast") == "force_cast")
        try shadow.applyRule("force_cast", isOptIn: false, isAnalyzer: false, parameterOverrides: nil)
        #expect(try nested().onlyRules == nil)
        #expect(try nested().disabledRules == ["force_cast"])
        #expect(try nested().excluded == ["Generated"])

        // A rule it lists is on there, and the config is written as it is.
        try shadow.applyRule("line_length", isOptIn: false, isAnalyzer: false, parameterOverrides: nil)
        #expect(try nested().onlyRules == ["line_length"])
        #expect(try nested().disabledRules == nil)

        // A rule linted with every rule sees the nested only_rules itself.
        try shadow.applyRule("superfluous_disable_command", isOptIn: false, isAnalyzer: false, parameterOverrides: nil)
        #expect(try nested().onlyRules == ["line_length"])
    }

    @Test("a nested only_rules SwiftLint rejects keeps every rule running, as written")
    func rejectedNestedOnlyRules() throws {
        let (shadow, workspace) = try makeShadow([
            "Sub/.swiftlint.yml": "only_rules:\n  - line_length\ndisabled_rules:\n  - todo\n"
        ])
        defer { shadow.cleanup(); try? FileManager.default.removeItem(at: workspace) }

        #expect(shadow.onlyRule(for: "force_cast") == nil)
    }

    @Test("a nested only_rules listing the rule, by any name, leaves it linted alone")
    func nestedOnlyRulesListingTheRule() throws {
        let (shadow, workspace) = try makeShadow([
            "Sub/.swiftlint.yml": "only_rules:\n  - variable_name\n",
            "Other/.swiftlint.yml": "only_rules: []\n"
        ])
        defer { shadow.cleanup(); try? FileManager.default.removeItem(at: workspace) }

        #expect(shadow.onlyRule(for: "identifier_name") == "identifier_name")
    }

    @Test("an only_rules in a config the root pulls in doesn't matter: the rule is enabled there")
    func referencedOnlyRules() throws {
        let (shadow, workspace) = try makeShadow([
            ".swiftlint.yml": "parent_config: base.yml\n",
            "base.yml": "only_rules:\n  - line_length\n"
        ])
        defer { shadow.cleanup(); try? FileManager.default.removeItem(at: workspace) }

        #expect(shadow.onlyRule(for: "force_cast") == "force_cast")
    }

    @Test("a nested only_rules keeps a rule off only when it names the rule by none of its names")
    func keepsOffReadsAliases() throws {
        let (shadow, workspace) = try makeShadow([
            "Sub/.swiftlint.yml": "only_rules:\n  - variable_name\n",
            "Other/.swiftlint.yml": "only_rules:\n  - line_length\n"
        ])
        defer { shadow.cleanup(); try? FileManager.default.removeItem(at: workspace) }
        let byAlias = try #require(shadow.configs.first { $0.relativePath.hasPrefix("Sub/") })
        let without = try #require(shadow.configs.first { $0.relativePath.hasPrefix("Other/") })

        #expect(!shadow.keepsOff("identifier_name", byAlias))
        #expect(shadow.keepsOff("identifier_name", without))
    }
}
