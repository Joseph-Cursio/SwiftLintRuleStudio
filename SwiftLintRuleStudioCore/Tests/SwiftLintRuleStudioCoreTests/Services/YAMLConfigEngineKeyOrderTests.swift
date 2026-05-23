import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

/// Regression tests for the SwiftAssist scenario: a `.swiftlint.yml` that
/// already has analyzer_rules + disabled_rules + opt_in_rules in a specific
/// order should round-trip through the engine without reorganizing blocks
/// or duplicating analyzer rules into opt_in_rules.
struct YAMLConfigEngineKeyOrderTests {

    private static let swiftAssistStyleYAML = """
    # Exclude common build and dependency directories
    excluded:
    - .build
    - Packages
    # Built-in rules we deliberately disable
    disabled_rules:
    - todo
    # Opt-in rules (enable specific rules that are valuable)
    opt_in_rules:
    - empty_count
    - force_unwrapping
    - closure_end_indentation
    # Analyzer-only rules (run via `swiftlint analyze`, not `swiftlint lint`)
    analyzer_rules:
    - capture_variable
    - unused_declaration
    - unused_import
    # Reporter type
    reporter: xcode
    """

    @Test("Round-trip preserves the original top-level key order")
    func testRoundTripPreservesKeyOrder() throws {
        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(
            content: Self.swiftAssistStyleYAML
        )
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let loadedConfig = try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            return engine.getConfig()
        }

        try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.save(config: loadedConfig, createBackup: false)
        }

        let savedContent = try String(contentsOf: configFile, encoding: .utf8)
        let keysInOrder = topLevelKeys(in: savedContent)

        #expect(
            keysInOrder == ["excluded", "disabled_rules", "opt_in_rules", "analyzer_rules", "reporter"],
            "Key order from the loaded file should survive a round-trip, got: \(keysInOrder)"
        )
    }

    @Test("Adding an opt-in rule does not duplicate analyzer rules into opt_in_rules")
    func testAddingOptInRuleDoesNotDuplicateAnalyzerRules() throws {
        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(
            content: Self.swiftAssistStyleYAML
        )
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        var config = try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            return engine.getConfig()
        }

        var optIn = config.optInRules ?? []
        optIn.append("accessibility_label_for_image")
        config.optInRules = optIn

        try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.save(config: config, createBackup: false)
        }

        let reloaded = try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            return engine.getConfig()
        }

        let optInRules = Set(reloaded.optInRules ?? [])
        let analyzerRules = Set(reloaded.analyzerRules ?? [])

        #expect(optInRules.contains("accessibility_label_for_image"), "New opt-in rule should be present")
        #expect(
            analyzerRules == ["capture_variable", "unused_declaration", "unused_import"],
            "Analyzer rules should be untouched, got: \(analyzerRules.sorted())"
        )
        let overlap = optInRules.intersection(analyzerRules)
        #expect(
            optInRules.isDisjoint(with: analyzerRules),
            "Analyzer rules should not be duplicated into opt_in_rules, overlap: \(overlap)"
        )
    }

    @Test("Adding an opt-in rule preserves original key order")
    func testAddingOptInRulePreservesKeyOrder() throws {
        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(
            content: Self.swiftAssistStyleYAML
        )
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        var config = try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            return engine.getConfig()
        }

        config.optInRules = (config.optInRules ?? []) + ["accessibility_label_for_image"]

        try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.save(config: config, createBackup: false)
        }

        let savedContent = try String(contentsOf: configFile, encoding: .utf8)
        let keysInOrder = topLevelKeys(in: savedContent)

        #expect(
            keysInOrder == ["excluded", "disabled_rules", "opt_in_rules", "analyzer_rules", "reporter"],
            "Adding a rule should not reorganize top-level blocks, got: \(keysInOrder)"
        )
    }

    /// Extract the top-level YAML keys from raw content in their original order.
    /// A "top-level key" is one on a line with no leading whitespace, not a comment,
    /// not a list item, and containing a colon.
    private func topLevelKeys(in content: String) -> [String] {
        var keys: [String] = []
        for rawLine in content.components(separatedBy: .newlines) {
            guard !rawLine.hasPrefix(" "), !rawLine.hasPrefix("\t") else { continue }
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("-") else { continue }
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colonIndex])
                .trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                keys.append(key)
            }
        }
        return keys
    }
}
