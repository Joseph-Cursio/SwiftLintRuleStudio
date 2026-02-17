//
//  ConfigImportService.swift
//  SwiftLintRuleStudio
//
//  Service for importing SwiftLint configurations from URLs
//

import Foundation

// MARK: - Types

enum ImportMode: Sendable {
    case replace
    case merge
}

struct ConfigImportPreview: Sendable {
    let sourceURL: URL
    let fetchedYAML: String
    let parsedConfig: YAMLConfigurationEngine.YAMLConfig
    let diff: YAMLConfigurationEngine.ConfigDiff?
    let validationErrors: [String]
}

// MARK: - Protocol

protocol ConfigImportServiceProtocol: Sendable {
    func fetchAndPreview(from url: URL, currentConfigPath: URL?) async throws -> ConfigImportPreview
    func applyImport(preview: ConfigImportPreview, mode: ImportMode, to configPath: URL) throws
}

// MARK: - Errors

enum ConfigImportError: LocalizedError, Sendable {
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

final class ConfigImportService: ConfigImportServiceProtocol, @unchecked Sendable {
    private let fetcher: URLConfigFetcherProtocol

    init(fetcher: URLConfigFetcherProtocol? = nil) {
        self.fetcher = fetcher ?? URLConfigFetcher()
    }

    func fetchAndPreview(from url: URL, currentConfigPath: URL?) async throws -> ConfigImportPreview {
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
            parsedConfig = try await MainActor.run {
                let engine = YAMLConfigurationEngine(configPath: tempFile)
                try engine.load()
                return engine.getConfig()
            }
        } catch {
            // Empty or comment-only YAML: return empty config with validation warning
            parsedConfig = await MainActor.run {
                YAMLConfigurationEngine.YAMLConfig()
            }
            validationErrors.append("Configuration appears empty - no rules defined.")
        }

        // Generate diff against current config if it exists
        var diff: YAMLConfigurationEngine.ConfigDiff?

        if let currentPath = currentConfigPath,
           FileManager.default.fileExists(atPath: currentPath.path) {
            diff = try await MainActor.run {
                let currentEngine = YAMLConfigurationEngine(configPath: currentPath)
                try currentEngine.load()
                return currentEngine.generateDiff(proposedConfig: parsedConfig)
            }
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

    @MainActor
    func applyImport(preview: ConfigImportPreview, mode: ImportMode, to configPath: URL) throws {
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
