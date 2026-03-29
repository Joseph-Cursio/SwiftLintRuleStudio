//
//  ConfigImportService.swift
//  SwiftLintRuleStudio
//
//  Service for importing SwiftLint configurations from URLs
//

import Foundation

// MARK: - Types

public enum ImportMode: Sendable {
    case replace
    case merge
}

public struct ConfigImportPreview: Sendable {
    public let sourceURL: URL
    public let fetchedYAML: String
    public let parsedConfig: YAMLConfigurationEngine.YAMLConfig
    public let diff: YAMLConfigurationEngine.ConfigDiff?
    public let validationErrors: [String]

    public init(
        sourceURL: URL,
        fetchedYAML: String,
        parsedConfig: YAMLConfigurationEngine.YAMLConfig,
        diff: YAMLConfigurationEngine.ConfigDiff?,
        validationErrors: [String]
    ) {
        self.sourceURL = sourceURL
        self.fetchedYAML = fetchedYAML
        self.parsedConfig = parsedConfig
        self.diff = diff
        self.validationErrors = validationErrors
    }
}

// MARK: - Protocol

public protocol ConfigImportServiceProtocol: Sendable {
    func fetchAndPreview(from url: URL, currentConfigPath: URL?) async throws -> ConfigImportPreview
    func applyImport(preview: ConfigImportPreview, mode: ImportMode, to configPath: URL) throws
}

// MARK: - Errors

private enum ConfigImportError: LocalizedError, Sendable {
    case fetchFailed(String)
    case parseFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .fetchFailed(let msg): return "Failed to fetch config: \(msg)"
        case .parseFailed(let msg): return "Failed to parse config: \(msg)"
        case .saveFailed(let msg): return "Failed to save config: \(msg)"
        }
    }
}

// MARK: - Implementation

public final class ConfigImportService: ConfigImportServiceProtocol, Sendable {
    private let fetcher: URLConfigFetcherProtocol

    public init(fetcher: URLConfigFetcherProtocol? = nil) {
        self.fetcher = fetcher ?? URLConfigFetcher()
    }

    public func fetchAndPreview(from url: URL, currentConfigPath: URL?) async throws -> ConfigImportPreview {
        let yamlContent = try await fetcher.fetchConfig(from: url)

        // Parse the fetched YAML
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tempFile = tempDir.appendingPathComponent(".swiftlint.yml")
        try yamlContent.write(to: tempFile, atomically: true, encoding: .utf8)

        var parsedConfig: YAMLConfigurationEngine.YAMLConfig
        var validationErrors: [String] = []

        do {
            let engine = YAMLConfigurationEngine(configPath: tempFile)
            try engine.load()
            parsedConfig = engine.getConfig()
        } catch {
            // Empty or comment-only YAML: return empty config with validation warning
            parsedConfig = YAMLConfigurationEngine.YAMLConfig()
            validationErrors.append("Configuration appears empty - no rules defined.")
        }

        // Generate diff against current config if it exists
        var diff: YAMLConfigurationEngine.ConfigDiff?

        if let currentPath = currentConfigPath,
           FileManager.default.fileExists(atPath: currentPath.path) {
            let currentEngine = YAMLConfigurationEngine(configPath: currentPath)
            try currentEngine.load()
            diff = currentEngine.generateDiff(proposedConfig: parsedConfig)
        }

        // Basic validation (only if no errors already added)
        if validationErrors.isEmpty
            && parsedConfig.rules.isEmpty
            && parsedConfig.disabledRules == nil
            && parsedConfig.optInRules == nil
            && parsedConfig.onlyRules == nil {
            validationErrors.append("Configuration appears empty - no rules defined.")
        }

        return ConfigImportPreview(
            sourceURL: url,
            fetchedYAML: yamlContent,
            parsedConfig: parsedConfig,
            diff: diff,
            validationErrors: validationErrors
        )
    }

    public func applyImport(preview: ConfigImportPreview, mode: ImportMode, to configPath: URL) throws {
        let engine = YAMLConfigurationEngine(configPath: configPath)

        switch mode {
        case .replace:
            try engine.save(config: preview.parsedConfig, createBackup: true)

        case .merge:
            // Load existing config and merge
            if FileManager.default.fileExists(atPath: configPath.path) {
                try engine.load()
                var merged = engine.getConfig()

                // Merge rules (imported overrides conflicts)
                for (ruleId, ruleConfig) in preview.parsedConfig.rules {
                    merged.rules[ruleId] = ruleConfig
                }

                // Merge list fields (union)
                if let importedDisabled = preview.parsedConfig.disabledRules {
                    var existing = Set(merged.disabledRules ?? [])
                    existing.formUnion(importedDisabled)
                    merged.disabledRules = Array(existing).sorted()
                }
                if let importedOptIn = preview.parsedConfig.optInRules {
                    var existing = Set(merged.optInRules ?? [])
                    existing.formUnion(importedOptIn)
                    merged.optInRules = Array(existing).sorted()
                }
                if let importedExcluded = preview.parsedConfig.excluded {
                    var existing = Set(merged.excluded ?? [])
                    existing.formUnion(importedExcluded)
                    merged.excluded = Array(existing).sorted()
                }

                try engine.save(config: merged, createBackup: true)
            } else {
                // No existing config, just save as-is
                try engine.save(config: preview.parsedConfig, createBackup: false)
            }
        }
    }
}
