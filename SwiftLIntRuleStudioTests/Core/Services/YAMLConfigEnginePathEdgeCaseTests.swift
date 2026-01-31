import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct YAMLConfigEnginePathEdgeCaseTests {
    @Test("YAMLConfigurationEngine handles multiple included paths")
    func testMultipleIncludedPaths() async throws {
        let yamlContent = """
        included:
          - Sources
          - Tests
          - Scripts
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let (includedCount, hasSources, hasTests, hasScripts) = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (
                config.included?.count ?? 0,
                config.included?.contains("Sources") == true,
                config.included?.contains("Tests") == true,
                config.included?.contains("Scripts") == true
            )
        }
        #expect(includedCount == 3)
        #expect(hasSources == true)
        #expect(hasTests == true)
        #expect(hasScripts == true)
    }

    @Test("YAMLConfigurationEngine handles multiple excluded paths")
    func testMultipleExcludedPaths() async throws {
        let yamlContent = """
        excluded:
          - Pods
          - .build
          - Generated
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let (excludedCount, hasPods, hasBuild, hasGenerated) = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (
                config.excluded?.count ?? 0,
                config.excluded?.contains("Pods") == true,
                config.excluded?.contains(".build") == true,
                config.excluded?.contains("Generated") == true
            )
        }
        #expect(excludedCount == 3)
        #expect(hasPods == true)
        #expect(hasBuild == true)
        #expect(hasGenerated == true)
    }

    @Test("YAMLConfigurationEngine handles reporter configuration")
    func testReporterConfiguration() async throws {
        let yamlContent = """
        reporter: xcode
        rules:
          force_cast: false
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let (reporter, forceCastEnabled) = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (
                config.reporter,
                config.rules["force_cast"]?.enabled
            )
        }
        #expect(reporter == "xcode")
        #expect(forceCastEnabled == false)
    }

    @Test("YAMLConfigurationEngine handles very large configuration")
    func testLargeConfiguration() async throws {
        var yamlContent = "rules:\n"
        for i in 1...50 {
            yamlContent += "  rule_\(i): true\n"
        }

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let rulesCount = try await YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return config.rules.count
        }
        #expect(rulesCount == 50)
    }

    @Test("YAMLConfigurationEngine handles rules with special characters in names")
    func testRulesWithSpecialCharacters() async throws {
        let yamlContent = """
        rules:
          "rule-with-dashes": true
          "rule_with_underscores": false
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let (dashesEnabled, underscoresEnabled) = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (
                config.rules["rule-with-dashes"]?.enabled,
                config.rules["rule_with_underscores"]?.enabled
            )
        }
        #expect(dashesEnabled == true)
        #expect(underscoresEnabled == false)
    }

    @Test("YAMLConfigurationEngine handles configuration with only rules")
    func testConfigurationWithOnlyRules() async throws {
        let yamlContent = """
        rules:
          force_cast: false
          line_length: true
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let (rulesCount, included, excluded, reporter) = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (
                config.rules.count,
                config.included,
                config.excluded,
                config.reporter
            )
        }
        #expect(rulesCount == 2)
        #expect(included == nil)
        #expect(excluded == nil)
        #expect(reporter == nil)
    }

    @Test("YAMLConfigurationEngine handles configuration with only included/excluded")
    func testConfigurationWithOnlyPaths() async throws {
        let yamlContent = """
        included:
          - Sources
        excluded:
          - Pods
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let (rulesEmpty, included, excluded) = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (
                config.rules.isEmpty,
                config.included,
                config.excluded
            )
        }
        #expect(rulesEmpty == true)
        #expect(included == ["Sources"])
        #expect(excluded == ["Pods"])
    }

    @Test("YAMLConfigurationEngine preserves rule order in diff")
    func testRuleOrderInDiff() async throws {
        let yamlContent = """
        rules:
          rule_a: true
          rule_b: false
          rule_c: true
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let (addedRules, addedRulesCount) = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            var config = engine.getConfig()
            config.rules["rule_d"] = RuleConfiguration(enabled: true)
            let diff = engine.generateDiff(proposedConfig: config)
            return (
                diff.addedRules,
                diff.addedRules.count
            )
        }
        #expect(addedRules.contains("rule_d"))
        #expect(addedRulesCount == 1)
    }
}
