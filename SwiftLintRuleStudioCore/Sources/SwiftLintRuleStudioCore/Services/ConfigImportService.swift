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

        // Parse the fetched YAML. This used to create a temporary directory, write
        // `yamlContent` into it, and construct an engine to read the file back — a round trip
        // through the filesystem to reach `parse(_:)`, which takes the string directly.
        var parsedConfig: YAMLConfigurationEngine.YAMLConfig
        var validationErrors: [String] = []

        do {
            parsedConfig = try YAMLConfigurationEngine.parse(yamlContent)
        } catch {
            // Empty or comment-only YAML: return empty config with validation warning
            parsedConfig = YAMLConfigurationEngine.YAMLConfig()
            validationErrors.append("Configuration appears empty - no rules defined.")
        }

        // Generate diff against current config if it exists
        var diff: YAMLConfigurationEngine.ConfigDiff?

        if let currentPath = currentConfigPath,
           FileManager.default.fileExists(atPath: currentPath.path) {
            diff = YAMLConfigurationEngine.diff(
                from: try YAMLConfigurationEngine.loadConfig(at: currentPath),
                to: parsedConfig
            )
        }

        // Basic validation (only if no errors already added)
        if validationErrors.isEmpty && parsedConfig.ruleIds.isEmpty {
            validationErrors.append("Configuration appears empty - no rules defined.")
        }
        if parsedConfig.hasOnlyRulesConflict {
            validationErrors.append(Self.onlyRulesConflictWarning)
        }

        return ConfigImportPreview(
            sourceURL: url,
            fetchedYAML: yamlContent,
            parsedConfig: parsedConfig,
            diff: diff,
            validationErrors: validationErrors
        )
    }

    /// Shown for an import SwiftLint itself would reject (issue #83); applying it is refused.
    static let onlyRulesConflictWarning = "SwiftLint rejects this configuration: it lists rules under "
        + "only_rules and also under opt_in_rules or disabled_rules, so it can't be imported."

    public func applyImport(preview: ConfigImportPreview, mode: ImportMode, to configPath: URL) throws {
        // Refused in both modes. Replace would write it as is, and Merge would quietly drop
        // half of it when the import's `only_rules` takes over.
        if preview.parsedConfig.hasOnlyRulesConflict {
            throw YAMLConfigError.onlyRulesConflict
        }
        switch mode {
        case .replace:
            // The imported file replaces this one, so it's the imported file's comments and
            // layout that should survive, not those of the file being replaced.
            try YAMLConfigurationEngine.save(
                preview.parsedConfig,
                to: configPath,
                keepingLayoutOf: .text(preview.fetchedYAML)
            )

        case .merge:
            // Load existing config and merge, or save the import as-is if none exists.
            if FileManager.default.fileExists(atPath: configPath.path) {
                let existing = try YAMLConfigurationEngine.loadConfig(at: configPath)
                // An existing file SwiftLint rejects is repaired through the app's previewed
                // fix, not here: an import with `only_rules` would clear its lists and save a
                // repair nobody reviewed.
                if existing.hasOnlyRulesConflict {
                    throw YAMLConfigError.onlyRulesConflict
                }
                let merged = Self.merge(existing: existing, imported: preview.parsedConfig)
                try YAMLConfigurationEngine.save(merged, to: configPath)
            } else {
                try YAMLConfigurationEngine.save(
                    preview.parsedConfig, to: configPath, createBackup: false
                )
            }
        }
    }

    /// Merge `imported` onto `existing`: imported rule configs override conflicts,
    /// every list field unions, and the scalar `reporter` is overridden when the
    /// import provides one.
    ///
    /// The rule lists combine the way SwiftLint combines a parent config with a child
    /// config, the import playing the child, so two files SwiftLint accepts merge into one it
    /// accepts. A plain union of every list used to put one file's `only_rules` beside the
    /// other's `opt_in_rules` or `disabled_rules` — the combination SwiftLint rejects
    /// (issue #83).
    ///
    /// - An import with `only_rules` replaces the existing `opt_in_rules` and
    ///   `disabled_rules`; its allowlist joins any the existing file already has.
    /// - An import without one folds into an existing `only_rules`: its opt-in rules join the
    ///   allowlist and its disabled rules leave it.
    /// - Two files without `only_rules` union every list, as before.
    ///
    /// `applyImport` refuses to merge into an existing file SwiftLint already rejects.
    static func merge(
        existing: YAMLConfigurationEngine.YAMLConfig,
        imported: YAMLConfigurationEngine.YAMLConfig
    ) -> YAMLConfigurationEngine.YAMLConfig {
        var merged = existing
        for (ruleId, ruleConfig) in imported.rules {
            merged.rules[ruleId] = ruleConfig
        }
        merged.excluded = unioned(merged.excluded, imported.excluded)
        merged.analyzerRules = unioned(merged.analyzerRules, imported.analyzerRules)
        merged.included = unioned(merged.included, imported.included)
        if let reporter = imported.reporter {
            merged.reporter = reporter
        }

        if imported.usesOnlyRules {
            merged.onlyRules = unioned(existing.usesOnlyRules ? existing.onlyRules : nil, imported.onlyRules)
            merged.optInRules = nil
            merged.disabledRules = nil
        } else {
            merged.disabledRules = unioned(merged.disabledRules, imported.disabledRules)
            merged.optInRules = unioned(merged.optInRules, imported.optInRules)
            merged.onlyRules = unioned(merged.onlyRules, imported.onlyRules)
        }
        return merged.normalizedRuleLists()
    }

    /// The sorted union of two optional string lists, or `existing` unchanged when
    /// `imported` is nil.
    private static func unioned(_ existing: [String]?, _ imported: [String]?) -> [String]? {
        guard let imported else { return existing }
        return Array(Set(existing ?? []).union(imported)).sorted()
    }
}
