//
//  YAMLConfigDisabledRulesRoundTripTests.swift
//  SwiftLintRuleStudioTests
//
//  Serializer contract for `disabled_rules`.
//
//  SwiftLint has no per-rule `enabled: false` key, so `disabled_rules` is the only
//  representation of a disabled *default* rule. Two rules govern this layer:
//
//  1. `disabled_rules` is emitted verbatim from `config.disabledRules`. The
//     serializer does NOT infer it from `config.rules` entries marked
//     `enabled == false`. It cannot: only default rules are disabled that way —
//     opt-in and analyzer rules are disabled by absence from `opt_in_rules` /
//     `analyzer_rules` — and `YAMLConfig` carries no rule metadata to tell them
//     apart. The callers that know the kind own that decision. An earlier revision
//     folded here and silently pushed every opt-in and analyzer rule into
//     `disabled_rules`; `foldIsNotPerformed` is the guard against that returning.
//
//  2. A disabled rule never also emits a config mapping. Verified against SwiftLint
//     0.65.0: a config carrying both warns "Found a configuration for 'line_length'
//     rule, but it is disabled in 'disabled_rules'."
//
//  That disabling a default rule *reaches* `config.disabledRules` in the first place
//  is a view-model concern, covered by RuleDetailViewModelAnalyzerRoutingTests and
//  RuleBrowserViewModelBulkTests.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing
import Yams

@MainActor
struct YAMLConfigDisabledRulesRoundTripTests {
    /// A config with neither a `rules:` block nor `disabled_rules`, so anything
    /// asserted about those keys was written by the code under test.
    private func makeMinimalConfig(content: String = "excluded:\n  - .build\n") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YAMLDisabledRulesTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configPath = dir.appendingPathComponent(".swiftlint.yml")
        try content.write(to: configPath, atomically: true, encoding: .utf8)
        return configPath
    }

    /// Saves `config` and returns the re-parsed raw YAML dictionary.
    private func savedYAML(
        _ engine: YAMLConfigurationEngine,
        _ config: YAMLConfigurationEngine.YAMLConfig
    ) throws -> [String: Any] {
        try engine.save(config: config, createBackup: false)
        let saved = try String(contentsOf: engine.configPath, encoding: .utf8)
        return try #require(try Yams.load(yaml: saved) as? [String: Any])
    }

    @Test("disabled_rules is emitted from config.disabledRules")
    func disabledRulesEmittedFromExplicitList() throws {
        let configPath = try makeMinimalConfig()
        defer { try? FileManager.default.removeItem(at: configPath.deletingLastPathComponent()) }

        let engine = YAMLConfigurationEngine(configPath: configPath)
        try engine.load()
        var config = engine.getConfig()
        config.disabledRules = ["trailing_whitespace"]

        let parsed = try savedYAML(engine, config)
        let disabled = try #require(parsed["disabled_rules"] as? [String], "disabled_rules must be emitted")
        #expect(disabled.contains("trailing_whitespace"))
    }

    @Test("A rule in disabled_rules round-trips as disabled after save and reload")
    func disabledRuleRoundTrips() throws {
        let configPath = try makeMinimalConfig()
        defer { try? FileManager.default.removeItem(at: configPath.deletingLastPathComponent()) }

        let engine = YAMLConfigurationEngine(configPath: configPath)
        try engine.load()
        var config = engine.getConfig()
        config.disabledRules = ["trailing_whitespace"]
        try engine.save(config: config, createBackup: false)

        // Reload from disk through a fresh engine, as the app would on next open.
        let reopened = YAMLConfigurationEngine(configPath: configPath)
        try reopened.load()
        #expect(reopened.getConfig().disabledRules?.contains("trailing_whitespace") == true,
                "the rule must still be disabled after a round-trip")
    }

    @Test("An existing disabled_rules list is preserved when another rule is added")
    func existingDisabledRulesPreserved() throws {
        let configPath = try makeMinimalConfig(content: "disabled_rules:\n  - nesting\n")
        defer { try? FileManager.default.removeItem(at: configPath.deletingLastPathComponent()) }

        let engine = YAMLConfigurationEngine(configPath: configPath)
        try engine.load()
        var config = engine.getConfig()
        config.disabledRules = (config.disabledRules ?? []) + ["trailing_whitespace"]

        let parsed = try savedYAML(engine, config)
        let disabled = try #require(parsed["disabled_rules"] as? [String])
        #expect(disabled.contains("nesting"), "the pre-existing disabled rule must survive")
        #expect(disabled.contains("trailing_whitespace"), "the newly disabled rule must be added")
    }

    @Test("A disabled rule is not also emitted as a contradictory config mapping")
    func disabledRuleOmitsConfigMapping() throws {
        let configPath = try makeMinimalConfig()
        defer { try? FileManager.default.removeItem(at: configPath.deletingLastPathComponent()) }

        let engine = YAMLConfigurationEngine(configPath: configPath)
        try engine.load()
        var config = engine.getConfig()
        // A rule that carried a custom severity and is now being disabled.
        config.rules["line_length"] = RuleConfiguration(enabled: false, severity: .error)
        config.disabledRules = ["line_length"]

        let parsed = try savedYAML(engine, config)
        let disabled = try #require(parsed["disabled_rules"] as? [String])
        #expect(disabled.contains("line_length"))
        #expect(parsed["line_length"] == nil,
                "a disabled rule must not also emit a severity mapping — SwiftLint 0.65.0 warns on it")
    }

    // Regression guard. `config.rules` entries marked `enabled == false` must NOT be
    // folded into `disabled_rules` here: this layer cannot tell a default rule from
    // an opt-in or analyzer rule, and folding pushed the latter two into a list where
    // they are inert noise. Kind-aware callers write `disabledRules` themselves.
    @Test("An enabled==false rule is not folded into disabled_rules by the serializer")
    func foldIsNotPerformed() throws {
        let configPath = try makeMinimalConfig()
        defer { try? FileManager.default.removeItem(at: configPath.deletingLastPathComponent()) }

        let engine = YAMLConfigurationEngine(configPath: configPath)
        try engine.load()
        var config = engine.getConfig()
        // Marked disabled in the working model, but no caller put it in disabledRules.
        config.rules["explicit_init"] = RuleConfiguration(enabled: false)

        let parsed = try savedYAML(engine, config)
        #expect(parsed["disabled_rules"] == nil,
                "the serializer must not invent a disabled_rules entry it cannot classify")
        #expect(parsed["explicit_init"] == nil,
                "a disabled rule still emits no config mapping")
    }
}
