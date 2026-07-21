//
//  YAMLConfigDisabledRulesRoundTripTests.swift
//  SwiftLintRuleStudioTests
//
//  Regression tests for P0.2: disabling a rule must actually disable it.
//
//  A rule marked `enabled == false` in `config.rules` must be serialized into the
//  top-level `disabled_rules` list — SwiftLint has no per-rule `enabled: false`
//  key, so this is the only representation that takes effect. This mirrors the
//  parse-side migration (a loaded `rules:` block's `enabled: false` entries are
//  already folded into `disabledRules`); without the matching serialize step, the
//  disabled state is silently dropped on save.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing
import Yams

@MainActor
struct YAMLConfigDisabledRulesRoundTripTests {
    /// A minimal config that contains neither a `rules:` block nor `disabled_rules`,
    /// so a newly-disabled rule has to be added from scratch (the plain-default case
    /// the previous bulk test never exercised).
    private func makeMinimalConfig() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YAMLDisabledRulesTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configPath = dir.appendingPathComponent(".swiftlint.yml")
        try "excluded:\n  - .build\n".write(to: configPath, atomically: true, encoding: .utf8)
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

    @Test("Marking a plain default rule disabled serializes it into disabled_rules")
    func disabledPlainRuleSerializesToDisabledRules() throws {
        let configPath = try makeMinimalConfig()
        defer { try? FileManager.default.removeItem(at: configPath.deletingLastPathComponent()) }

        let engine = YAMLConfigurationEngine(configPath: configPath)
        try engine.load()
        var config = engine.getConfig()
        // Exactly what disableSelectedRules does to a plain default rule.
        config.rules["trailing_whitespace"] = RuleConfiguration(enabled: false)

        let parsed = try savedYAML(engine, config)
        let disabled = try #require(parsed["disabled_rules"] as? [String], "disabled_rules must be emitted")
        #expect(disabled.contains("trailing_whitespace"))
    }

    @Test("A disabled rule round-trips as disabled after save and reload")
    func disabledRuleRoundTrips() throws {
        let configPath = try makeMinimalConfig()
        defer { try? FileManager.default.removeItem(at: configPath.deletingLastPathComponent()) }

        let engine = YAMLConfigurationEngine(configPath: configPath)
        try engine.load()
        var config = engine.getConfig()
        config.rules["trailing_whitespace"] = RuleConfiguration(enabled: false)
        try engine.save(config: config, createBackup: false)

        // Reload from disk through a fresh engine, as the app would on next open.
        let reopened = YAMLConfigurationEngine(configPath: configPath)
        try reopened.load()
        let reloaded = reopened.getConfig()
        #expect(reloaded.disabledRules?.contains("trailing_whitespace") == true,
                "the rule must still be disabled after a round-trip")
    }

    @Test("An existing disabled_rules list is preserved when another rule is disabled")
    func existingDisabledRulesPreserved() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YAMLDisabledRulesTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configPath = dir.appendingPathComponent(".swiftlint.yml")
        try "disabled_rules:\n  - nesting\n".write(to: configPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let engine = YAMLConfigurationEngine(configPath: configPath)
        try engine.load()
        var config = engine.getConfig()
        config.rules["trailing_whitespace"] = RuleConfiguration(enabled: false)

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

        let parsed = try savedYAML(engine, config)
        let disabled = try #require(parsed["disabled_rules"] as? [String])
        #expect(disabled.contains("line_length"))
        #expect(parsed["line_length"] == nil,
                "a disabled rule must not also emit a severity mapping that contradicts disabled_rules")
    }
}
