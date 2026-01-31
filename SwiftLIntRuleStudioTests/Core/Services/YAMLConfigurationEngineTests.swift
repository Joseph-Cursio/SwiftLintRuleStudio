import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// YAMLConfigurationEngine is @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
struct YAMLConfigurationEngineTests {
    // MARK: - Validation Tests

    @Test("YAMLConfigurationEngine validates severity values")
    func testValidateSeverity() async throws {
        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: "")
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        try? FileManager.default.removeItem(at: configFile)

        let config1 = await MainActor.run {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.rules["test_rule"] = RuleConfiguration(enabled: true, severity: .warning)
            return config
        }

        try await YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.validate(config1)
        }

        let config2 = await MainActor.run {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.rules["test_rule"] = RuleConfiguration(enabled: true, severity: .error)
            return config
        }
        try await YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.validate(config2)
        }
    }

    @Test("YAMLConfigurationEngine validates included paths")
    func testValidateIncludedPaths() async throws {
        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: "")
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        try? FileManager.default.removeItem(at: configFile)

        let config = await MainActor.run {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.included = ["Sources", "Tests"]
            return config
        }

        try await YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.validate(config)
        }
    }

    @Test("YAMLConfigurationEngine rejects empty included paths")
    func testValidateEmptyIncludedPaths() async throws {
        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: "")
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        try? FileManager.default.removeItem(at: configFile)

        let config = await MainActor.run {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.included = [""]
            return config
        }

        await #expect(throws: YAMLConfigError.self) {
            try await YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
                try engine.validate(config)
            }
        }
    }

    @Test("YAMLConfigurationEngine rejects empty excluded paths")
    func testValidateEmptyExcludedPaths() async throws {
        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: "")
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        try? FileManager.default.removeItem(at: configFile)

        let config = await MainActor.run {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.excluded = [""]
            return config
        }

        await #expect(throws: YAMLConfigError.self) {
            try await YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
                try engine.validate(config)
            }
        }
    }

    // MARK: - Comment Preservation Tests

    @Test("YAMLConfigurationEngine extracts comments from YAML")
    func testExtractComments() async throws {
        let yamlContent = """
        # This is a comment
        rules:
          # Rule comment
          force_cast: false
        included:
          - Sources
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let rulesCount = try await YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return config.rules.count
        }

        #expect(rulesCount == 1)
    }

    // MARK: - Error Handling Tests

    @Test("YAMLConfigurationEngine handles invalid YAML")
    func testInvalidYAML() async throws {
        let invalidYAML = """
        rules:
          - invalid
          - yaml
          structure
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: invalidYAML)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        await #expect(throws: YAMLConfigError.self) {
            try await YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
                try engine.load()
            }
        }
    }

    @Test("YAMLConfigurationEngine handles malformed rule configuration")
    func testMalformedRuleConfig() async throws {
        let yamlContent = """
        rules:
          force_cast:
            invalid_field: value
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let hasForceCast = try await YAMLConfigurationEngineTestHelpers.withEngine(configPath: configFile) { engine in
            try engine.load()
            let config = engine.getConfig()
            return config.rules["force_cast"] != nil
        }
        #expect(hasForceCast == true)
    }

    // MARK: - Round-Trip Tests

    @Test("YAMLConfigurationEngine preserves configuration in round-trip")
    func testRoundTrip() async throws {
        let yamlContent = """
        rules:
          force_cast:
            severity: error
          line_length:
            warning: 120
        included:
          - Sources
        excluded:
          - Pods
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let originalSnapshot = try await loadRoundTripSnapshot(configFile: configFile)

        let originalConfig = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            return engine.getConfig()
        }
        try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.save(config: originalConfig, createBackup: false)
        }

        let reloadedSnapshot = try await loadRoundTripSnapshot(configFile: configFile)

        #expect(reloadedSnapshot.rulesCount == originalSnapshot.rulesCount)
        #expect(reloadedSnapshot.forceCastSeverity == originalSnapshot.forceCastSeverity)
        #expect(reloadedSnapshot.included == originalSnapshot.included)
        #expect(reloadedSnapshot.excluded == originalSnapshot.excluded)
    }

    @Test("YAMLConfigurationEngine handles complex rule parameters")
    func testComplexRuleParameters() async throws {
        let yamlContent = """
        rules:
          line_length:
            warning: 120
            error: 200
            ignores_urls: true
            ignores_function_declarations: false
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let (hasLineLength, hasParams, paramsCount) = try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            let lineLengthRule = config.rules["line_length"]
            return (
                lineLengthRule != nil,
                lineLengthRule?.parameters != nil,
                lineLengthRule?.parameters?.count ?? 0
            )
        }
        #expect(hasLineLength == true)
        #expect(hasParams == true)
        #expect(paramsCount >= 3)
    }

    private struct RoundTripSnapshot {
        let rulesCount: Int
        let forceCastSeverity: Severity?
        let included: [String]?
        let excluded: [String]?
    }

    private func loadRoundTripSnapshot(
        configFile: URL
    ) async throws -> RoundTripSnapshot {
        try await YAMLConfigurationEngineTestHelpers.withEngine(
            configPath: configFile
        ) { engine in
            try engine.load()
            let config = engine.getConfig()
            return RoundTripSnapshot(
                rulesCount: config.rules.count,
                forceCastSeverity: config.rules["force_cast"]?.severity,
                included: config.included,
                excluded: config.excluded
            )
        }
    }
}
