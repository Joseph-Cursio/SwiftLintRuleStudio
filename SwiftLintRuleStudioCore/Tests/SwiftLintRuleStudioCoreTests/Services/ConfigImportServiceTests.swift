//
//  ConfigImportServiceTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for ConfigImportService
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

private final class MockURLConfigFetcher: URLConfigFetcherProtocol, @unchecked Sendable {
    let yamlContent: String

    init(yamlContent: String) {
        self.yamlContent = yamlContent
    }

    func fetchConfig(from _: URL) throws -> String {
        yamlContent
    }

    func validateURL(_: URL) -> URLValidationResult {
        .valid
    }
}

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
        let existingConfig = try createTempConfig(
            content: "force_cast:\n  severity: warning\n"
        )
        defer { cleanup(existingConfig) }

        var importedConfig = YAMLConfigurationEngine.YAMLConfig()
        importedConfig.rules = ["line_length": RuleConfiguration(enabled: true, severity: .warning)]

        let preview = ConfigImportPreview(
            sourceURL: try #require(URL(string: "https://example.com/.swiftlint.yml")),
            fetchedYAML: "line_length:\n  severity: warning\n",
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
        let existingConfig = try createTempConfig(
            content: "force_cast:\n  severity: warning\n"
        )
        defer { cleanup(existingConfig) }

        var importedConfig = YAMLConfigurationEngine.YAMLConfig()
        importedConfig.rules = ["line_length": RuleConfiguration(enabled: true, severity: .warning)]

        let preview = ConfigImportPreview(
            sourceURL: try #require(URL(string: "https://example.com/.swiftlint.yml")),
            fetchedYAML: "line_length:\n  severity: warning\n",
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

    // Regression for P3: merge mode dropped analyzer_rules, only_rules, included,
    // and reporter — importing a config carrying any of them silently lost them.
    @Test("Merge mode preserves analyzer_rules, only_rules, included, and reporter")
    func testMergePreservesRemainingFields() throws {
        let existingConfig = try createTempConfig(content: "force_cast:\n  severity: warning\n")
        defer { cleanup(existingConfig) }

        var importedConfig = YAMLConfigurationEngine.YAMLConfig()
        importedConfig.analyzerRules = ["unused_import"]
        importedConfig.onlyRules = ["line_length"]
        importedConfig.included = ["Sources"]
        importedConfig.reporter = "json"

        let preview = ConfigImportPreview(
            sourceURL: try #require(URL(string: "https://example.com/.swiftlint.yml")),
            fetchedYAML: "analyzer_rules:\n  - unused_import\n",
            parsedConfig: importedConfig,
            diff: nil,
            validationErrors: []
        )

        try ConfigImportService().applyImport(preview: preview, mode: .merge, to: existingConfig)

        let engine = YAMLConfigurationEngine(configPath: existingConfig)
        try engine.load()
        let config = engine.getConfig()
        #expect(config.analyzerRules?.contains("unused_import") == true)
        #expect(config.onlyRules?.contains("line_length") == true)
        #expect(config.included?.contains("Sources") == true)
        #expect(config.reporter == "json")
    }

    // MARK: - Merge across rules modes (issue #83)

    private func merged(existing: String, imported: YAMLConfigurationEngine.YAMLConfig) throws
        -> YAMLConfigurationEngine.YAMLConfig {
        let existingConfig = try createTempConfig(content: existing)
        defer { cleanup(existingConfig) }
        let preview = ConfigImportPreview(
            sourceURL: try #require(URL(string: "https://example.com/.swiftlint.yml")),
            fetchedYAML: "",
            parsedConfig: imported,
            diff: nil,
            validationErrors: []
        )
        try ConfigImportService().applyImport(preview: preview, mode: .merge, to: existingConfig)
        return try YAMLConfigurationEngine.loadConfig(at: existingConfig)
    }

    @Test("Merging a default-mode import into only_rules folds it in, as SwiftLint folds a child config")
    func testMergeDefaultImportIntoOnlyRules() throws {
        var imported = YAMLConfigurationEngine.YAMLConfig()
        imported.optInRules = ["empty_count"]
        imported.disabledRules = ["line_length"]

        let config = try merged(existing: "only_rules:\n  - force_cast\n  - line_length\n", imported: imported)

        #expect(config.onlyRules == ["force_cast", "empty_count"])
        #expect(config.optInRules == nil)
        #expect(config.disabledRules == nil)
    }

    @Test("Merging an only_rules import replaces the existing opt_in_rules and disabled_rules")
    func testMergeOnlyRulesImportIntoDefaultMode() throws {
        var imported = YAMLConfigurationEngine.YAMLConfig()
        imported.onlyRules = ["force_cast", "line_length"]

        let config = try merged(
            existing: "disabled_rules:\n  - line_length\nopt_in_rules:\n  - empty_count\n",
            imported: imported
        )

        #expect(config.onlyRules == ["force_cast", "line_length"])
        #expect(config.optInRules == nil)
        #expect(config.disabledRules == nil)
    }

    @Test("Merging two only_rules files unions the allowlists and keeps analyzer rules out of them")
    func testMergeTwoOnlyRulesFiles() throws {
        var imported = YAMLConfigurationEngine.YAMLConfig()
        imported.onlyRules = ["line_length", "unused_import"]
        imported.analyzerRules = ["unused_import"]

        let config = try merged(existing: "only_rules:\n  - force_cast\n", imported: imported)

        #expect(config.onlyRules == ["force_cast", "line_length"])
        #expect(config.analyzerRules == ["unused_import"])
    }

    @Test("Merging into an existing file SwiftLint already rejects is refused, whatever the import's mode")
    func testMergeIntoConflictedFileIsRefused() throws {
        let conflicted = "only_rules:\n  - force_cast\n  - line_length\ndisabled_rules:\n  - line_length\n"
        var onlyImport = YAMLConfigurationEngine.YAMLConfig()
        onlyImport.onlyRules = ["todo"]
        var defaultImport = YAMLConfigurationEngine.YAMLConfig()
        defaultImport.optInRules = ["empty_count"]

        for imported in [onlyImport, defaultImport] {
            let existingConfig = try createTempConfig(content: conflicted)
            defer { cleanup(existingConfig) }
            let preview = ConfigImportPreview(
                sourceURL: try #require(URL(string: "https://example.com/.swiftlint.yml")),
                fetchedYAML: "",
                parsedConfig: imported,
                diff: nil,
                validationErrors: []
            )
            #expect(throws: YAMLConfigError.self) {
                try ConfigImportService().applyImport(preview: preview, mode: .merge, to: existingConfig)
            }
            #expect(try String(contentsOf: existingConfig, encoding: .utf8) == conflicted)
        }
    }

    @Test("An import SwiftLint would reject is warned in the preview and refused on apply")
    func testConflictedImportIsRefused() async throws {
        let yaml = "only_rules:\n  - force_cast\nopt_in_rules:\n  - empty_count\n"
        let service = ConfigImportService(fetcher: MockURLConfigFetcher(yamlContent: yaml))
        let preview = try await service.fetchAndPreview(
            from: try #require(URL(string: "https://example.com/.swiftlint.yml")),
            currentConfigPath: nil
        )
        #expect(preview.validationErrors.contains(ConfigImportService.onlyRulesConflictWarning))

        let existingConfig = try createTempConfig(content: "force_cast:\n  severity: warning\n")
        defer { cleanup(existingConfig) }
        for mode in [ImportMode.replace, .merge] {
            #expect(throws: YAMLConfigError.self) {
                try service.applyImport(preview: preview, mode: mode, to: existingConfig)
            }
        }
        #expect(try String(contentsOf: existingConfig, encoding: .utf8) == "force_cast:\n  severity: warning\n")
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
            sourceURL: try #require(URL(string: "https://example.com/.swiftlint.yml")),
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
            from: try #require(URL(string: "https://example.com/.swiftlint.yml")),
            currentConfigPath: nil
        )

        #expect(preview.validationErrors.isEmpty == false)
    }

    // MARK: - Diff Generation

    @Test("Preview generates diff against existing config")
    func testPreviewGeneratesDiff() async throws {
        let existingConfig = try createTempConfig(content: "rules:\n  force_cast: true\n")
        defer { cleanup(existingConfig) }

        let fetcher = MockURLConfigFetcher(yamlContent: "rules:\n  line_length: true\n")
        let service = ConfigImportService(fetcher: fetcher)

        let preview = try await service.fetchAndPreview(
            from: try #require(URL(string: "https://example.com/.swiftlint.yml")),
            currentConfigPath: existingConfig
        )

        #expect(preview.diff != nil)
        #expect(preview.diff?.hasChanges == true)
    }
}
