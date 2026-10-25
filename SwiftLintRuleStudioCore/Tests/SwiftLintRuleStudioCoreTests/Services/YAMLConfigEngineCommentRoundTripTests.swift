import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

/// Regression coverage for comment handling when a top-level key is removed
/// from a configuration between load and save, through both `save` and `serialize(_:)`.
///
/// Previously, removing a key (e.g. emptying `disabled_rules` to `nil`) left a
/// stale entry in `config.comments`; the shared comment preserver could not
/// anchor it and appended the orphaned comment to the end of the file, with a
/// blank line and no trailing newline.
struct YAMLConfigEngineCommentRoundTripTests {
    @Test("Removing disabled_rules drops its comment instead of orphaning it to EOF", arguments: ConfigWriter.allCases)
    func removedKeyCommentNotOrphaned(writer: ConfigWriter) throws {
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

        var config = try YAMLConfigurationEngine.loadConfig(at: configFile)
        config.disabledRules = nil
        let savedYAML = try writer.text(of: config, over: configFile)

        // The dropped key and its comment are both gone.
        #expect(savedYAML.contains("disabled_rules") == false)
        #expect(savedYAML.contains("# Built-in rules we deliberately disable") == false)

        // The file is not corrupted: it ends with a single trailing newline,
        // not a dangling comment after blank lines.
        #expect(savedYAML.hasSuffix("\n"))
        #expect(savedYAML.hasSuffix("\n\n") == false)
    }

    @Test("Removing one key keeps comments anchored to the keys that remain", arguments: ConfigWriter.allCases)
    func survivingKeysKeepTheirComments(writer: ConfigWriter) throws {
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

        var config = try YAMLConfigurationEngine.loadConfig(at: configFile)
        config.disabledRules = nil
        let savedYAML = try writer.text(of: config, over: configFile)

        // Comments for surviving keys stay directly above their anchor key.
        #expect(savedYAML.contains("# Exclude build output\nexcluded:"))
        #expect(savedYAML.contains("# Opt-in rules worth enabling\nopt_in_rules:"))
    }

    @Test("Enabling the only disabled rule produces a clean, reloadable file", arguments: ConfigWriter.allCases)
    func enablingLastDisabledRuleProducesCleanFile(writer: ConfigWriter) throws {
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
        var config = try YAMLConfigurationEngine.loadConfig(at: configFile)
        config.disabledRules?.removeAll { $0 == "todo" }
        if config.disabledRules?.isEmpty == true { config.disabledRules = nil }
        let savedYAML = try writer.text(of: config, over: configFile)
        #expect(savedYAML.contains("disabled_rules") == false)
        #expect(savedYAML.contains("# Built-in rules we deliberately disable") == false)
        #expect(savedYAML.hasSuffix("\n"))

        // The saved file still parses, and the surviving config is intact.
        let reloaded = try YAMLConfigurationEngine.parse(savedYAML)

        #expect(reloaded.disabledRules == nil)
        #expect(reloaded.optInRules?.contains("empty_count") == true)
    }

    @Test("Round-trip with no removed keys leaves every comment in place", arguments: ConfigWriter.allCases)
    func roundTripPreservesLiveComments(writer: ConfigWriter) throws {
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

        let config = try YAMLConfigurationEngine.loadConfig(at: configFile)
        let savedYAML = try writer.text(of: config, over: configFile)

        #expect(savedYAML.contains("# Exclude build output\nexcluded:"))
        #expect(savedYAML.contains("# Built-in rules we deliberately disable\ndisabled_rules:"))
        #expect(savedYAML.contains("# Opt-in rules worth enabling\nopt_in_rules:"))
        #expect(savedYAML.hasSuffix("\n"))
        #expect(savedYAML.hasSuffix("\n\n") == false)
    }

    @Test("A multi-line comment block above a key survives a round-trip intact", arguments: ConfigWriter.allCases)
    func multiLineCommentBlockPreserved(writer: ConfigWriter) throws {
        let yamlContent = """
        # First line of the rationale
        # Second line of the rationale
        # Third line of the rationale
        excluded:
        - .build
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let config = try YAMLConfigurationEngine.loadConfig(at: configFile)
        let savedYAML = try writer.text(of: config, over: configFile)

        // All three comment lines survive, in order, directly above the key —
        // not collapsed to just the last line, and not reversed.
        #expect(savedYAML.contains("""
        # First line of the rationale
        # Second line of the rationale
        # Third line of the rationale
        excluded:
        """))
    }

    @Test("Regenerated block sequence items are indented two spaces under their key")
    func sequenceItemsIndentedUnderKey() throws {
        // Saving keeps an unchanged list exactly as written (see YAMLConfigEngineLayoutTests);
        // this is the style of the lists `serialize(_:)` writes from scratch.
        let config = try YAMLConfigurationEngine.parse("""
        included:
        - Sources
        - Tests
        """)

        let serialized = try YAMLConfigurationEngine.serialize(config)

        #expect(serialized.contains("included:\n  - Sources\n  - Tests"))
        // No item is left flush against column zero.
        #expect(serialized.contains("\n- Sources") == false)
    }
}
