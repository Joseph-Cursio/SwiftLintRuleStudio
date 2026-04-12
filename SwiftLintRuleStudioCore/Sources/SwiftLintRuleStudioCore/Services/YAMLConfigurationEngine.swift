//
//  YAMLConfigurationEngine.swift
//  SwiftLintRuleStudio
//
//  Created for YAML configuration editing with comment preservation
//

import Foundation
import Yams
import LintStudioCore

/// Service for safely editing SwiftLint YAML configuration files
/// with comment preservation and validation
public class YAMLConfigurationEngine {

    // MARK: - Types

    /// Represents a YAML configuration with preserved comments
    public struct YAMLConfig {
        /// Rule configurations keyed by rule identifier
        public var rules: [String: RuleConfiguration]
        /// Paths to include in analysis
        public var included: [String]?
        /// Paths to exclude from analysis
        public var excluded: [String]?
        /// The reporter format
        public var reporter: String?
        /// Rules to disable
        public var disabledRules: [String]?
        /// Opt-in rules to enable
        public var optInRules: [String]?
        /// Analyzer rules to enable
        public var analyzerRules: [String]?
        /// Only these rules will be active
        public var onlyRules: [String]?
        /// Warning threshold count
        public var warningThreshold: Int?
        /// Whether strict mode is enabled
        public var strict: Bool?

        // Comment preservation
        /// Preserved comments mapped by YAML key path
        public var comments: [String: String] = [:]
        /// Preserved ordering of top-level YAML keys
        public var keyOrder: [String] = []

        /// Create an empty YAML configuration
        public init() {
            self.rules = [:]
            self.included = nil
            self.excluded = nil
            self.reporter = nil
            self.disabledRules = nil
            self.optInRules = nil
            self.analyzerRules = nil
            self.onlyRules = nil
            self.warningThreshold = nil
            self.strict = nil
        }
    }

    /// Represents a diff between two configurations
    public struct ConfigDiff: Identifiable {
        public let id = UUID()
        public let addedRules: [String]
        public let removedRules: [String]
        public let modifiedRules: [String]
        public let before: String
        public let after: String

        public var hasChanges: Bool {
            !addedRules.isEmpty || !removedRules.isEmpty || !modifiedRules.isEmpty
        }

        public init(
            addedRules: [String],
            removedRules: [String],
            modifiedRules: [String],
            before: String,
            after: String
        ) {
            self.addedRules = addedRules
            self.removedRules = removedRules
            self.modifiedRules = modifiedRules
            self.before = before
            self.after = after
        }
    }

    // MARK: - Properties

    /// Path to the `.swiftlint.yml` configuration file
    public let configPath: URL
    /// The original file content before modifications
    public var originalContent: String = ""
    /// The current in-memory configuration state
    public var currentConfig: YAMLConfig = YAMLConfig()

    // MARK: - Initialization

    /// Initialize the engine with the path to a `.swiftlint.yml` file
    public init(configPath: URL) {
        self.configPath = configPath
    }

    // MARK: - Loading

    /// Load configuration from file
    public func load() throws {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            // File doesn't exist, start with empty config
            currentConfig = YAMLConfig()
            originalContent = ""
            return
        }

        // Read raw content for comment preservation
        originalContent = try String(contentsOf: configPath, encoding: .utf8)

        // Parse YAML (this loses comments)
        // Yams uses Node-based API, so we'll parse to dictionary first
        guard let yamlString = try? String(contentsOf: configPath, encoding: .utf8) else {
            throw YAMLConfigError.parseError("Could not read file")
        }

        do {
            // Parse YAML to Node, then convert to our model
            let node = try Yams.compose(yaml: yamlString)
            guard let node = node else {
                throw YAMLConfigError.parseError("Empty YAML document")
            }

            // Convert Node to dictionary for easier parsing
            let dict = try nodeToDictionary(node)
            let parsed = try parseDictionaryToConfig(dict)

            // Convert to our config model
            currentConfig = YAMLConfig()
            currentConfig.rules = parsed.rules
            currentConfig.included = parsed.included
            currentConfig.excluded = parsed.excluded
            currentConfig.reporter = parsed.reporter
            currentConfig.disabledRules = parsed.disabledRules
            currentConfig.optInRules = parsed.optInRules
            currentConfig.analyzerRules = parsed.analyzerRules
            currentConfig.onlyRules = parsed.onlyRules

            // Extract comments from original content
            extractComments(from: originalContent)
            extractKeyOrder(from: originalContent)
        } catch {
            throw YAMLConfigError.parseError(error.localizedDescription)
        }
    }

    /// Get current configuration
    public func getConfig() -> YAMLConfig {
        return currentConfig
    }

    /// Update configuration (doesn't save to disk)
    public func updateConfig(_ config: YAMLConfig) {
        currentConfig = config
    }

    // MARK: - Saving

    /// Generate diff between current and proposed configuration
    public func generateDiff(proposedConfig: YAMLConfig) -> ConfigDiff {
        let currentRules = Set(currentConfig.rules.keys)
        let proposedRules = Set(proposedConfig.rules.keys)

        let addedRules = Array(proposedRules.subtracting(currentRules))
        let removedRules = Array(currentRules.subtracting(proposedRules))
        let modifiedRules = currentRules.intersection(proposedRules).filter { ruleId in
            currentConfig.rules[ruleId] != proposedConfig.rules[ruleId]
        }

        let before = try? serialize(currentConfig)
        let after = try? serialize(proposedConfig)

        return ConfigDiff(
            addedRules: addedRules.sorted(),
            removedRules: removedRules.sorted(),
            modifiedRules: Array(modifiedRules).sorted(),
            before: before ?? "",
            after: after ?? ""
        )
    }

    /// Validate configuration before saving
    public func validate(_ config: YAMLConfig) throws {
        // Check for invalid rule IDs (basic validation)
        // More comprehensive validation can be added later

        // Validate severity values
        for (ruleId, ruleConfig) in config.rules {
            if let severity = ruleConfig.severity {
                if severity != .warning && severity != .error {
                    throw YAMLConfigError.invalidSeverity(ruleId: ruleId, severity: severity.rawValue)
                }
            }
        }

        // Validate file paths in included/excluded
        if let included = config.included {
            for path in included where path.isEmpty {
                throw YAMLConfigError.invalidPath(path: path)
            }
        }

        if let excluded = config.excluded {
            for path in excluded where path.isEmpty {
                throw YAMLConfigError.invalidPath(path: path)
            }
        }
    }

    /// Save configuration to file with backup
    public func save(config: YAMLConfig, createBackup: Bool = true) throws {
        // Validate before saving
        try validate(config)

        // Serialize to YAML
        let yamlContent = try serialize(config)

        // Atomic write with optional backup via shared SafeFileWriter
        try SafeFileWriter.write(yamlContent, to: configPath, createBackup: createBackup)

        // Update current config
        currentConfig = config
        originalContent = yamlContent
    }

}

// MARK: - Errors

public enum YAMLConfigError: LocalizedError, Sendable {
    case parseError(String)
    case serializationError(String)
    case invalidSeverity(ruleId: String, severity: String)
    case invalidPath(path: String)
    case fileNotFound
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .parseError(let message):
            return "Failed to parse YAML: \(message)"
        case .serializationError(let message):
            return "Failed to serialize YAML: \(message)"
        case .invalidSeverity(let ruleId, let severity):
            return "Invalid severity '\(severity)' for rule '\(ruleId)'. Must be 'warning' or 'error'."
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .fileNotFound:
            return "Configuration file not found"
        case .writeFailed(let message):
            return "Failed to write configuration: \(message)"
        }
    }
}
