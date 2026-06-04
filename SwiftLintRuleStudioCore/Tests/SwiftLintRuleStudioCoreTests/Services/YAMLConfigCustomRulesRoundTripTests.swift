//
//  YAMLConfigCustomRulesRoundTripTests.swift
//  SwiftLintRuleStudioTests
//
//  Regression: editing a config (e.g. adding force_unwrapping) via
//  YAMLConfigurationEngine must not drop unmodeled top-level keys such as
//  `custom_rules`. Exercised against a real user's full config.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing
import Yams

@MainActor
struct YAMLConfigCustomRulesRoundTripTests {

    // The user's actual config. A raw string so the custom-rule regex
    // (`^\t* +\t*\S`) is preserved verbatim, exactly as in their .swiftlint.yml.
    private static let sourceConfig = #"""
    identifier_name:
      min_length: 2
      excluded:
       - x
       - y
       - T
    type_name:
      allowed_symbols:
        - "_"
      max_length: 100
    line_length: 120
    file_length: 800
    type_body_length:
      warning: 500
    number_separator:
      minimum_length: 5
    trailing_comma:
      mandatory_comma: true
    function_body_length:
      warning: 120
      error: 150
    opening_brace:
      ignore_multiline_statement_conditions: true
    attributes:
      always_on_same_line: ["@IBAction", "@NSManaged", "@Test"]
      always_on_line_above: ["@NHActor"]

    disabled_rules:
      - nesting
      - closing_brace
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
    excluded:
      - .build

    custom_rules:
      leading_whitespace:
        name: Tabs
        message: Use tab indentation
        regex: ^\t* +\t*\S
        severity: error
    """#

    private func makeConfigFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YAMLCustomRulesTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configPath = dir.appendingPathComponent(".swiftlint.yml")
        try Self.sourceConfig.write(to: configPath, atomically: true, encoding: .utf8)
        return configPath
    }

    /// Loads the config, adds force_unwrapping to opt_in_rules, saves, and
    /// returns the re-parsed result.
    private func roundTripAddingForceUnwrapping(_ configPath: URL) throws -> [String: Any] {
        let engine = YAMLConfigurationEngine(configPath: configPath)
        try engine.load()
        var config = engine.getConfig()
        config.optInRules = (config.optInRules ?? []) + ["force_unwrapping"]
        try engine.save(config: config, createBackup: false)

        let saved = try String(contentsOf: configPath, encoding: .utf8)
        return try #require(try Yams.load(yaml: saved) as? [String: Any])
    }

    @Test("adding force_unwrapping preserves custom_rules and its regex verbatim")
    func testCustomRulesSurvive() throws {
        let configPath = try makeConfigFile()
        defer { try? FileManager.default.removeItem(at: configPath.deletingLastPathComponent()) }

        let parsed = try roundTripAddingForceUnwrapping(configPath)

        let optInRules = try #require(parsed["opt_in_rules"] as? [String])
        #expect(optInRules.contains("force_unwrapping"))
        #expect(optInRules.contains("number_separator"))

        let customRules = try #require(parsed["custom_rules"] as? [String: Any])
        let tabsRule = try #require(customRules["leading_whitespace"] as? [String: Any])
        #expect(tabsRule["regex"] as? String == #"^\t* +\t*\S"#)
        #expect(tabsRule["message"] as? String == "Use tab indentation")
        #expect(tabsRule["severity"] as? String == "error")
    }

    @Test("adding force_unwrapping preserves the rest of the config")
    func testOtherKeysSurvive() throws {
        let configPath = try makeConfigFile()
        defer { try? FileManager.default.removeItem(at: configPath.deletingLastPathComponent()) }

        let parsed = try roundTripAddingForceUnwrapping(configPath)

        #expect(parsed["line_length"] as? Int == 120)
        #expect(parsed["disabled_rules"] as? [String] == ["nesting", "closing_brace"])
        #expect(parsed["excluded"] as? [String] == [".build"])

        let attributes = try #require(parsed["attributes"] as? [String: Any])
        #expect(attributes["always_on_same_line"] as? [String] == ["@IBAction", "@NSManaged", "@Test"])
        #expect(attributes["always_on_line_above"] as? [String] == ["@NHActor"])

        let identifierName = try #require(parsed["identifier_name"] as? [String: Any])
        #expect(identifierName["excluded"] as? [String] == ["x", "y", "T"])
    }
}
