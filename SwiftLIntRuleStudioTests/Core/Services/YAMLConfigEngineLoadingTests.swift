import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// YAMLConfigurationEngine is @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
struct YAMLConfigEngineLoadingTests {
    @Test("YAMLConfigurationEngine loads existing configuration file")
    func testLoadExistingFile() async throws {
        let yamlContent = """
        disabled_rules:
          - force_cast
        opt_in_rules:
          - empty_count
        included:
          - Sources
        excluded:
          - Pods
        reporter: xcode
        rules:
          line_length:
            warning: 120
            error: 200
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        struct ConfigSnapshot {
            let included: [String]?
            let excluded: [String]?
            let reporter: String?
            let rulesCount: Int
            let hasLineLength: Bool
        }

        let snapshot = try await MainActor.run {
            let engine = YAMLConfigurationEngine(configPath: configFile)
            try engine.load()
            let config = engine.getConfig()
            return ConfigSnapshot(
                included: config.included,
                excluded: config.excluded,
                reporter: config.reporter,
                rulesCount: config.rules.count,
                hasLineLength: config.rules["line_length"] != nil
            )
        }

        #expect(snapshot.included == ["Sources"])
        #expect(snapshot.excluded == ["Pods"])
        #expect(snapshot.reporter == "xcode")
        #expect(snapshot.rulesCount == 1)
        #expect(snapshot.hasLineLength == true)
    }

    @Test("YAMLConfigurationEngine handles non-existent file")
    func testLoadNonExistentFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configFile = tempDir.appendingPathComponent(".swiftlint.yml")

        let (rulesEmpty, included, excluded) = try await MainActor.run {
            let engine = YAMLConfigurationEngine(configPath: configFile)
            try engine.load()
            let config = engine.getConfig()
            return (
                config.rules.isEmpty,
                config.included,
                config.excluded
            )
        }

        #expect(rulesEmpty == true)
        #expect(included == nil)
        #expect(excluded == nil)
    }

    @Test("YAMLConfigurationEngine parses simple rule configuration")
    func testParseSimpleRuleConfig() async throws {
        let yamlContent = """
        rules:
          force_cast:
            severity: error
          line_length:
            warning: 120
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let parseSnapshot = try await MainActor.run {
            let engine = YAMLConfigurationEngine(configPath: configFile)
            try engine.load()
            let config = engine.getConfig()
            return (
                rulesCount: config.rules.count,
                forceCastSeverity: config.rules["force_cast"]?.severity,
                hasLineLengthParams: config.rules["line_length"]?.parameters != nil
            )
        }

        #expect(parseSnapshot.rulesCount == 2)
        #expect(parseSnapshot.forceCastSeverity == .error)
        #expect(parseSnapshot.hasLineLengthParams == true)
    }

    @Test("YAMLConfigurationEngine parses boolean rule configuration")
    func testParseBooleanRuleConfig() async throws {
        let yamlContent = """
        rules:
          force_cast: false
          line_length: true
        """

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        let (rulesCount, forceCastEnabled, lineLengthEnabled) = try await MainActor.run {
            let engine = YAMLConfigurationEngine(configPath: configFile)
            try engine.load()
            let config = engine.getConfig()
            return (
                config.rules.count,
                config.rules["force_cast"]?.enabled,
                config.rules["line_length"]?.enabled
            )
        }

        #expect(rulesCount == 2)
        #expect(forceCastEnabled == false)
        #expect(lineLengthEnabled == true)
    }

    @Test("YAMLConfigurationEngine handles empty configuration")
    func testLoadEmptyConfiguration() async throws {
        let yamlContent = ""

        let configFile = try YAMLConfigurationEngineTestHelpers.createTempConfigFile(content: yamlContent)
        defer { YAMLConfigurationEngineTestHelpers.cleanupTempFile(configFile) }

        await #expect(throws: YAMLConfigError.self) {
            try await MainActor.run {
                let engine = YAMLConfigurationEngine(configPath: configFile)
                try engine.load()
            }
        }
    }
}
