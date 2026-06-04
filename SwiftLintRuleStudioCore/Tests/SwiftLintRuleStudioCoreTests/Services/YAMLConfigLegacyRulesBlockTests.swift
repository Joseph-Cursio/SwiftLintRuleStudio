//
//  YAMLConfigLegacyRulesBlockTests.swift
//  SwiftLintRuleStudioTests
//
//  A config that mixes a legacy `rules:` block with opt_in_rules must parse
//  completely and round-trip without losing the real (modeled) data.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing
import Yams

@MainActor
struct YAMLConfigLegacyRulesBlockTests {

    private static let sourceConfig = """
    disabled_rules:
    - nesting
    - closing_brace
    excluded:
    - .build
    opt_in_rules:
    - number_separator
    - closure_spacing
    - overridden_super_call
    - attributes
    - fatal_error_message
    - empty_count
    - redundant_nil_coalescing
    - first_where
    - operator_usage_whitespace
    - prohibited_super_call
    - force_unwrapping
    rules:
      force_unwrapping: true
    """

    private func makeConfigFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YAMLLegacyRulesTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configPath = dir.appendingPathComponent(".swiftlint.yml")
        try Self.sourceConfig.write(to: configPath, atomically: true, encoding: .utf8)
        return configPath
    }

    @Test("the config parses completely into the model")
    func testParsesCompletely() throws {
        let configPath = try makeConfigFile()
        defer { try? FileManager.default.removeItem(at: configPath.deletingLastPathComponent()) }

        let engine = YAMLConfigurationEngine(configPath: configPath)
        try engine.load()
        let config = engine.getConfig()

        #expect(config.disabledRules == ["nesting", "closing_brace"])
        #expect(config.excluded == [".build"])
        let optIn = try #require(config.optInRules)
        #expect(optIn.contains("force_unwrapping"))
        #expect(optIn.contains("number_separator"))
        #expect(optIn.count == 11)
        // The legacy `rules:` block is parsed too.
        #expect(config.rules["force_unwrapping"]?.enabled == true)
    }

    @Test("round-trip preserves the real data (force_unwrapping stays enabled)")
    func testRoundTripPreservesData() throws {
        let configPath = try makeConfigFile()
        defer { try? FileManager.default.removeItem(at: configPath.deletingLastPathComponent()) }

        let engine = YAMLConfigurationEngine(configPath: configPath)
        try engine.load()
        try engine.save(config: engine.getConfig(), createBackup: false)

        let saved = try String(contentsOf: configPath, encoding: .utf8)
        let parsed = try #require(try Yams.load(yaml: saved) as? [String: Any])

        #expect(parsed["disabled_rules"] as? [String] == ["nesting", "closing_brace"])
        #expect(parsed["excluded"] as? [String] == [".build"])
        let optIn = try #require(parsed["opt_in_rules"] as? [String])
        #expect(optIn.contains("force_unwrapping"))
        #expect(optIn.count == 11)
    }
}
