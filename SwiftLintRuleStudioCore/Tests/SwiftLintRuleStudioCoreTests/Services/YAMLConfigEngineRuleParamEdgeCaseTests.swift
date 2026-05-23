import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct YAMLConfigEngineRuleParamEdgeCaseTests {
    private struct NumericScalarSnapshot {
        let warningType: String
        let errorType: String
        let warningValue: Int?
        let errorValue: Int?
        let ignoresCommentsType: String
        let typeLevelValue: Int?
        let serialized: String
    }

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
        #expect(ruleSnapshot.hasRule)
        #expect(ruleSnapshot.hasParams)
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
        #expect(disabledSnapshot.hasParams)
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
        #expect(rulesEmpty)
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
        #expect(hasParams)
        #expect(hasWarning)
        #expect(hasError)
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
        #expect(hasParams)
        #expect(hasName)
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
        #expect(hasParams)
        #expect(hasPaths)
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
        #expect(hasParams)
        #expect(hasTypeLevel)
        #expect(hasFunctionLevel)
    }

    // Regression: unquoted YAML integers arrive as plain-style Yams scalars
    // with no explicit tag. The parser previously fell through to "treat as
    // String", so re-serialization emitted `error: '150'` instead of
    // `error: 150` — which SwiftLint rejects as "Invalid configuration for
    // 'line_length' rule. Falling back to default."
    @Test("Plain-style numeric scalars parse as Int and survive re-serialize")
    func testNumericScalarsRoundTripAsIntegers() async throws {
        let yamlContent = """
        line_length:
          warning: 120
          error: 150
          ignores_comments: true
        nesting:
          type_level: 2
          function_level: 3
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let snapshot = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            let lineLength = config.rules["line_length"]
            let nesting = config.rules["nesting"]
            let warning = lineLength?.parameters?["warning"]?.value
            let lineError = lineLength?.parameters?["error"]?.value
            let ignoresComments = lineLength?.parameters?["ignores_comments"]?.value
            let typeLevel = nesting?.parameters?["type_level"]?.value
            let serialized = try engine.serialize(engine.getConfig())
            return NumericScalarSnapshot(
                warningType: String(describing: type(of: warning ?? "")),
                errorType: String(describing: type(of: lineError ?? "")),
                warningValue: warning as? Int,
                errorValue: lineError as? Int,
                ignoresCommentsType: String(describing: type(of: ignoresComments ?? "")),
                typeLevelValue: typeLevel as? Int,
                serialized: serialized
            )
        }

        #expect(snapshot.warningValue == 120)
        #expect(snapshot.errorValue == 150)
        #expect(snapshot.typeLevelValue == 2)
        #expect(snapshot.warningType == "Int", "Got \(snapshot.warningType)")
        #expect(snapshot.errorType == "Int", "Got \(snapshot.errorType)")
        #expect(snapshot.ignoresCommentsType == "Bool", "Got \(snapshot.ignoresCommentsType)")

        // Re-serialized output must emit unquoted integers; quoting them as
        // `'120'` would make SwiftLint reject the rule configuration.
        #expect(!snapshot.serialized.contains("'120'"))
        #expect(!snapshot.serialized.contains("'150'"))
        #expect(!snapshot.serialized.contains("\"120\""))
        #expect(!snapshot.serialized.contains("\"150\""))
        #expect(snapshot.serialized.contains("warning: 120"))
        #expect(snapshot.serialized.contains("error: 150"))
    }
}
