//
//  ConfigImportServiceTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for ConfigImportService
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

@MainActor
struct ConfigImportServiceTests {

    // MARK: - Helpers

    private func createTempConfig(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigImportTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        try content.write(to: configPath, atomically: true, encoding: .utf8)
        return configPath
    }

    private func createTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigImportTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir.appendingPathComponent(".swiftlint.yml")
    }

    private func cleanup(_ path: URL) {
        try? FileManager.default.removeItem(at: path.deletingLastPathComponent())
    }

    // MARK: - Replace Mode

    @Test("Replace mode overwrites existing config")
    func testReplaceMode() throws {
        let existingConfig = try createTempConfig(content: "rules:\n  force_cast: true\n")
        defer { cleanup(existingConfig) }

        var importedConfig = YAMLConfigurationEngine.YAMLConfig()
        importedConfig.rules = ["line_length": RuleConfiguration(enabled: true)]

        let preview = ConfigImportPreview(
            sourceURL: URL(string: "https://example.com/.swiftlint.yml")!,
            fetchedYAML: "rules:\n  line_length: true\n",
            parsedConfig: importedConfig,
            diff: nil,
            validationErrors: []
        )

        let service = ConfigImportService()
        try service.applyImport(preview: preview, mode: .replace, to: existingConfig)

        // Read back and verify
        let engine = YAMLConfigurationEngine(configPath: existingConfig)
        try engine.load()
        let config = engine.getConfig()
        #expect(config.rules["line_length"] != nil)
        #expect(config.rules["force_cast"] == nil)
    }

    // MARK: - Merge Mode

    @Test("Merge mode combines rules")
    func testMergeMode() throws {
        let existingConfig = try createTempConfig(content: "rules:\n  force_cast: true\n")
        defer { cleanup(existingConfig) }

        var importedConfig = YAMLConfigurationEngine.YAMLConfig()
        importedConfig.rules = ["line_length": RuleConfiguration(enabled: true)]

        let preview = ConfigImportPreview(
            sourceURL: URL(string: "https://example.com/.swiftlint.yml")!,
            fetchedYAML: "rules:\n  line_length: true\n",
            parsedConfig: importedConfig,
            diff: nil,
            validationErrors: []
        )

        let service = ConfigImportService()
        try service.applyImport(preview: preview, mode: .merge, to: existingConfig)

        let engine = YAMLConfigurationEngine(configPath: existingConfig)
        try engine.load()
        let config = engine.getConfig()
        #expect(config.rules["line_length"] != nil)
        #expect(config.rules["force_cast"] != nil)
    }

    // MARK: - Merge Override

    @Test("Merge mode: imported rules override conflicts")
    func testMergeOverridesConflicts() throws {
        let existingConfig = try createTempConfig(
            content: "rules:\n  line_length:\n    severity: warning\n"
        )
        defer { cleanup(existingConfig) }

        var importedConfig = YAMLConfigurationEngine.YAMLConfig()
        importedConfig.rules = ["line_length": RuleConfiguration(enabled: true, severity: .error)]

        let preview = ConfigImportPreview(
            sourceURL: URL(string: "https://example.com/.swiftlint.yml")!,
            fetchedYAML: "rules:\n  line_length:\n    severity: error\n",
            parsedConfig: importedConfig,
            diff: nil,
            validationErrors: []
        )

        let service = ConfigImportService()
        try service.applyImport(preview: preview, mode: .merge, to: existingConfig)

        let engine = YAMLConfigurationEngine(configPath: existingConfig)
        try engine.load()
        let config = engine.getConfig()
        #expect(config.rules["line_length"]?.severity == .error)
    }

    // MARK: - Empty Validation

    @Test("Preview detects empty config warning")
    func testEmptyConfigWarning() async throws {
        let fetcher = MockURLConfigFetcher(yamlContent: "# empty config\n")
        let service = ConfigImportService(fetcher: fetcher)

        let preview = try await service.fetchAndPreview(
            from: URL(string: "https://example.com/.swiftlint.yml")!,
            currentConfigPath: nil
        )

        #expect(!preview.validationErrors.isEmpty)
    }

    // MARK: - Diff Generation

    @Test("Preview generates diff against existing config")
    func testPreviewGeneratesDiff() async throws {
        let existingConfig = try createTempConfig(content: "rules:\n  force_cast: true\n")
        defer { cleanup(existingConfig) }

        let fetcher = MockURLConfigFetcher(yamlContent: "rules:\n  line_length: true\n")
        let service = ConfigImportService(fetcher: fetcher)

        let preview = try await service.fetchAndPreview(
            from: URL(string: "https://example.com/.swiftlint.yml")!,
            currentConfigPath: existingConfig
        )

        #expect(preview.diff != nil)
        #expect(preview.diff?.hasChanges == true)
    }
}

// MARK: - Mock Fetcher

private final class MockURLConfigFetcher: URLConfigFetcherProtocol, @unchecked Sendable {
    let yamlContent: String

    init(yamlContent: String) {
        self.yamlContent = yamlContent
    }

    func fetchConfig(from url: URL) async throws -> String {
        return yamlContent
    }

    func validateURL(_ url: URL) -> URLValidationResult {
        return .valid
    }
}
