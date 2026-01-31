import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct YAMLConfigEngineRuleParamEdgeCaseTests {
    @Test("YAMLConfigurationEngine handles rules with only parameters, no severity")
    func testRulesWithOnlyParameters() async throws {
        let yamlContent = """
        rules:
          line_length:
            warning: 120
            error: 200
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let ruleSnapshot = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (
                hasRule: config.rules["line_length"] != nil,
                hasParams: config.rules["line_length"]?.parameters != nil,
                severity: config.rules["line_length"]?.severity
            )
        }
        #expect(ruleSnapshot.hasRule == true)
        #expect(ruleSnapshot.hasParams == true)
        #expect(ruleSnapshot.severity == nil)
    }

    @Test("YAMLConfigurationEngine handles disabled rules with parameters")
    func testDisabledRulesWithParameters() async throws {
        let yamlContent = """
        rules:
          line_length:
            enabled: false
            warning: 120
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let disabledSnapshot = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (
                enabled: config.rules["line_length"]?.enabled,
                hasParams: config.rules["line_length"]?.parameters != nil
            )
        }
        #expect(disabledSnapshot.enabled == false)
        #expect(disabledSnapshot.hasParams == true)
    }

    @Test("YAMLConfigurationEngine handles empty rules dictionary")
    func testEmptyRulesDictionary() async throws {
        let yamlContent = """
        rules: {}
        included:
          - Sources
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let (rulesEmpty, included) = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (
                config.rules.isEmpty,
                config.included
            )
        }
        #expect(rulesEmpty == true)
        #expect(included == ["Sources"])
    }

    @Test("YAMLConfigurationEngine handles numeric rule parameters")
    func testNumericRuleParameters() async throws {
        let yamlContent = """
        rules:
          file_length:
            warning: 400
            error: 1000
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let (hasParams, hasWarning, hasError) = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            let fileLengthRule = config.rules["file_length"]
            return (
                fileLengthRule?.parameters != nil,
                fileLengthRule?.parameters?["warning"] != nil,
                fileLengthRule?.parameters?["error"] != nil
            )
        }
        #expect(hasParams == true)
        #expect(hasWarning == true)
        #expect(hasError == true)
    }

    @Test("YAMLConfigurationEngine handles string rule parameters")
    func testStringRuleParameters() async throws {
        let yamlContent = """
        rules:
          custom_rules:
            name: "My Custom Rule"
            regex: ".*"
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let (hasParams, hasName) = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (
                config.rules["custom_rules"]?.parameters != nil,
                config.rules["custom_rules"]?.parameters?["name"] != nil
            )
        }
        #expect(hasParams == true)
        #expect(hasName == true)
    }

    @Test("YAMLConfigurationEngine handles array rule parameters")
    func testArrayRuleParameters() async throws {
        let yamlContent = """
        rules:
          excluded:
            paths:
              - Pods
              - Generated
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let (hasParams, hasPaths) = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            return (
                config.rules["excluded"]?.parameters != nil,
                config.rules["excluded"]?.parameters?["paths"] != nil
            )
        }
        #expect(hasParams == true)
        #expect(hasPaths == true)
    }

    @Test("YAMLConfigurationEngine handles nested rule configurations")
    func testNestedRuleConfigurations() async throws {
        let yamlContent = """
        rules:
          nesting:
            type_level: 2
            function_level: 3
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let (hasParams, hasTypeLevel, hasFunctionLevel) = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            let nestingRule = config.rules["nesting"]
            return (
                nestingRule?.parameters != nil,
                nestingRule?.parameters?["type_level"] != nil,
                nestingRule?.parameters?["function_level"] != nil
            )
        }
        #expect(hasParams == true)
        #expect(hasTypeLevel == true)
        #expect(hasFunctionLevel == true)
    }
}
