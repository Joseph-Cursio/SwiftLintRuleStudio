import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

/// Regression coverage for comment handling when a top-level key is removed
/// from a configuration between load and save.
///
/// Previously, removing a key (e.g. emptying `disabled_rules` to `nil`) left a
/// stale entry in `config.comments`; the shared comment preserver could not
/// anchor it and appended the orphaned comment to the end of the file, with a
/// blank line and no trailing newline.
struct YAMLConfigEngineCommentRoundTripTests {
    @Test("Removing disabled_rules drops its comment instead of orphaning it to EOF")
    func removedKeyCommentNotOrphaned() async throws {
        let yamlContent = """
        # Exclude build output
        excluded:
        - .build
        # Built-in rules we deliberately disable
        disabled_rules:
        - todo
        # Opt-in rules worth enabling
        opt_in_rules:
        - empty_count
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            var config = engine.getConfig()
            config.disabledRules = nil
            try engine.save(config: config, createBackup: false)
        }

        let savedYAML = try String(contentsOf: configFile, encoding: .utf8)

        // The dropped key and its comment are both gone.
        #expect(savedYAML.contains("disabled_rules") == false)
        #expect(savedYAML.contains("# Built-in rules we deliberately disable") == false)

        // The file is not corrupted: it ends with a single trailing newline,
        // not a dangling comment after blank lines.
        #expect(savedYAML.hasSuffix("\n"))
        #expect(savedYAML.hasSuffix("\n\n") == false)
    }

    @Test("Removing one key keeps comments anchored to the keys that remain")
    func survivingKeysKeepTheirComments() async throws {
        let yamlContent = """
        # Exclude build output
        excluded:
        - .build
        # Built-in rules we deliberately disable
        disabled_rules:
        - todo
        # Opt-in rules worth enabling
        opt_in_rules:
        - empty_count
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            var config = engine.getConfig()
            config.disabledRules = nil
            try engine.save(config: config, createBackup: false)
        }

        let savedYAML = try String(contentsOf: configFile, encoding: .utf8)

        // Comments for surviving keys stay directly above their anchor key.
        #expect(savedYAML.contains("# Exclude build output\nexcluded:"))
        #expect(savedYAML.contains("# Opt-in rules worth enabling\nopt_in_rules:"))
    }

    @Test("Enabling the only disabled rule produces a clean, reloadable file")
    func enablingLastDisabledRuleProducesCleanFile() async throws {
        let yamlContent = """
        # Built-in rules we deliberately disable
        disabled_rules:
        - todo
        # Opt-in rules worth enabling
        opt_in_rules:
        - empty_count
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        // Simulate enabling `todo`: remove it from disabled_rules. An emptied
        // list collapses to nil, exactly as the rule-toggle helpers do.
        try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            var config = engine.getConfig()
            config.disabledRules?.removeAll { $0 == "todo" }
            if config.disabledRules?.isEmpty == true { config.disabledRules = nil }
            try engine.save(config: config, createBackup: false)
        }

        let savedYAML = try String(contentsOf: configFile, encoding: .utf8)
        #expect(savedYAML.contains("disabled_rules") == false)
        #expect(savedYAML.contains("# Built-in rules we deliberately disable") == false)
        #expect(savedYAML.hasSuffix("\n"))

        // The saved file still parses, and the surviving config is intact.
        let reloaded = try YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (disabledRules: config.disabledRules, optInRules: config.optInRules)
        }

        #expect(reloaded.disabledRules == nil)
        #expect(reloaded.optInRules?.contains("empty_count") == true)
    }

    @Test("Round-trip with no removed keys leaves every comment in place")
    func roundTripPreservesLiveComments() async throws {
        let yamlContent = """
        # Exclude build output
        excluded:
        - .build
        # Built-in rules we deliberately disable
        disabled_rules:
        - todo
        # Opt-in rules worth enabling
        opt_in_rules:
        - empty_count
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            try engine.save(config: config, createBackup: false)
        }

        let savedYAML = try String(contentsOf: configFile, encoding: .utf8)

        #expect(savedYAML.contains("# Exclude build output\nexcluded:"))
        #expect(savedYAML.contains("# Built-in rules we deliberately disable\ndisabled_rules:"))
        #expect(savedYAML.contains("# Opt-in rules worth enabling\nopt_in_rules:"))
        #expect(savedYAML.hasSuffix("\n"))
        #expect(savedYAML.hasSuffix("\n\n") == false)
    }

    @Test("A multi-line comment block above a key survives a round-trip intact")
    func multiLineCommentBlockPreserved() async throws {
        let yamlContent = """
        # First line of the rationale
        # Second line of the rationale
        # Third line of the rationale
        excluded:
        - .build
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            try engine.save(config: config, createBackup: false)
        }

        let savedYAML = try String(contentsOf: configFile, encoding: .utf8)

        // All three comment lines survive, in order, directly above the key —
        // not collapsed to just the last line, and not reversed.
        #expect(savedYAML.contains("""
        # First line of the rationale
        # Second line of the rationale
        # Third line of the rationale
        excluded:
        """))
    }

    @Test("Block sequence items are indented two spaces under their key")
    func sequenceItemsIndentedUnderKey() async throws {
        let yamlContent = """
        included:
        - Sources
        - Tests
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        try YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            try engine.save(config: config, createBackup: false)
        }

        let savedYAML = try String(contentsOf: configFile, encoding: .utf8)

        #expect(savedYAML.contains("included:\n  - Sources\n  - Tests"))
        // No item is left flush against column zero.
        #expect(savedYAML.contains("\n- Sources") == false)
    }
}
