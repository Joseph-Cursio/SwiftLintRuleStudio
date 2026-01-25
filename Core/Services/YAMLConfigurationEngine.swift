//
//  YAMLConfigurationEngine.swift
//  SwiftLintRuleStudio
//
//  Created for YAML configuration editing with comment preservation
//

import Foundation
import Yams

/// Service for safely editing SwiftLint YAML configuration files
/// with comment preservation and validation
@MainActor
class YAMLConfigurationEngine {
    
    // MARK: - Types
    
    /// Represents a YAML configuration with preserved comments
    struct YAMLConfig {
        var rules: [String: RuleConfiguration]
        var included: [String]?
        var excluded: [String]?
        var reporter: String?
        var disabledRules: [String]?
        var optInRules: [String]?
        var analyzerRules: [String]?
        var onlyRules: [String]?
        var warningThreshold: Int?
        var strict: Bool?
        
        // Comment preservation
        var comments: [String: String] = [:] // Key path -> comment text
        var keyOrder: [String] = [] // Preserve original key order
        
        init() {
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
    struct ConfigDiff {
        let addedRules: [String]
        let removedRules: [String]
        let modifiedRules: [String]
        let before: String
        let after: String
        
        var hasChanges: Bool {
            !addedRules.isEmpty || !removedRules.isEmpty || !modifiedRules.isEmpty
        }
    }
    
    // MARK: - Properties
    
    let configPath: URL
    var originalContent: String = ""
    var currentConfig: YAMLConfig = YAMLConfig()
    
    // MARK: - Initialization
    
    init(configPath: URL) {
        self.configPath = configPath
    }
    
    // MARK: - Loading
    
    /// Load configuration from file
    func load() throws {
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
    func getConfig() -> YAMLConfig {
        return currentConfig
    }
    
    /// Update configuration (doesn't save to disk)
    func updateConfig(_ config: YAMLConfig) {
        currentConfig = config
    }
    
    // MARK: - Saving
    
    /// Generate diff between current and proposed configuration
    func generateDiff(proposedConfig: YAMLConfig) -> ConfigDiff {
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
    func validate(_ config: YAMLConfig) throws {
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
    func save(config: YAMLConfig, createBackup: Bool = true) throws {
        // Validate before saving
        try validate(config)
        
        // Create backup if requested
        // IMPORTANT: Create backup BEFORE we modify the file
        if createBackup {
            // Check if original file exists (before any modifications)
            let fileExists = FileManager.default.fileExists(atPath: configPath.path)
            if fileExists {
                // Use timestamped backup filename to avoid conflicts in parallel operations
                let timestamp = Int(Date().timeIntervalSince1970)
                let backupFileName = "\(configPath.lastPathComponent).\(timestamp).backup"
                let backupPath = configPath.deletingLastPathComponent().appendingPathComponent(backupFileName)
                // Remove existing backup if it exists (shouldn't happen with timestamp, but be safe)
                if FileManager.default.fileExists(atPath: backupPath.path) {
                    try FileManager.default.removeItem(at: backupPath)
                }
                // Create backup by copying the original file
                try FileManager.default.copyItem(at: configPath, to: backupPath)
            }
        }
        
        // Serialize to YAML
        let yamlContent = try serialize(config)
        
        // Atomic write: write to temp file, then move
        // Use UUID in temp filename to avoid conflicts in parallel operations
        let tempFileName = "\(configPath.lastPathComponent).\(UUID().uuidString).tmp"
        let tempFile = configPath.deletingLastPathComponent().appendingPathComponent(tempFileName)
        try yamlContent.write(to: tempFile, atomically: true, encoding: .utf8)
        
        // Move temp file to final location atomically
        // Remove destination if it exists (can happen in parallel test execution)
        // This ensures no race conditions if multiple operations happen in parallel
        if FileManager.default.fileExists(atPath: configPath.path) {
            try FileManager.default.removeItem(at: configPath)
        }
        try FileManager.default.moveItem(at: tempFile, to: configPath)
        
        // Update current config
        currentConfig = config
        originalContent = yamlContent
    }
    
}

// MARK: - Errors

enum YAMLConfigError: LocalizedError {
    case parseError(String)
    case serializationError(String)
    case invalidSeverity(ruleId: String, severity: String)
    case invalidPath(path: String)
    case fileNotFound
    case writeFailed(String)
    
    var errorDescription: String? {
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
