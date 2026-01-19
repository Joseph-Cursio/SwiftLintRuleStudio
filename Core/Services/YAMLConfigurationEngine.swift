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
    
    private let configPath: URL
    private var originalContent: String = ""
    private var currentConfig: YAMLConfig = YAMLConfig()
    
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
    
    // MARK: - Serialization
    
    private func serialize(_ config: YAMLConfig) throws -> String {
        // Convert to SwiftLintConfiguration for encoding
        var swiftLintConfig = SwiftLintConfiguration()
        swiftLintConfig.rules = config.rules
        swiftLintConfig.included = config.included
        swiftLintConfig.excluded = config.excluded
        swiftLintConfig.reporter = config.reporter
        
        // Encode to YAML using Yams
        do {
            // Convert to dictionary for Yams encoding
            let dict = configToDictionary(config)
            let node = try Node(dict)
            // Yams.serialize returns a String directly
            let yamlString = try Yams.serialize(node: node)
            
            // Reinsert comments if possible
            return reinsertComments(into: yamlString, config: config)
        } catch {
            throw YAMLConfigError.serializationError(error.localizedDescription)
        }
    }
    
    // MARK: - Yams Node Conversion
    
    private func nodeToDictionary(_ node: Node) throws -> [String: Any] {
        guard case .mapping(let mapping) = node else {
            throw YAMLConfigError.parseError("Expected mapping node")
        }
        
        var dict: [String: Any] = [:]
        for (keyNode, valueNode) in mapping {
            guard let key = keyNode.string else {
                continue
            }
            
            switch valueNode {
            case .scalar(let scalar):
                // Use Yams' built-in type detection
                let stringValue = scalar.string
                // Check tag description for type information
                let tagDescription = String(describing: scalar.tag)
                // Yams uses specific tag names for types
                if tagDescription.contains("bool") || tagDescription.contains("tag:yaml.org,2002:bool") {
                    dict[key] = stringValue == "true"
                } else if tagDescription.contains("int") || tagDescription.contains("tag:yaml.org,2002:int") {
                    dict[key] = Int(stringValue) ?? stringValue
                } else if tagDescription.contains("float") || tagDescription.contains("tag:yaml.org,2002:float") {
                    dict[key] = Double(stringValue) ?? stringValue
                } else if stringValue == "true" || stringValue == "false" {
                    // Fallback: if it looks like a boolean, treat it as one
                    dict[key] = stringValue == "true"
                } else {
                    dict[key] = stringValue
                }
            case .mapping:
                dict[key] = try nodeToDictionary(valueNode)
            case .sequence(let sequence):
                var array: [Any] = []
                for item in sequence {
                    if case .scalar(let scalar) = item {
                        let stringValue = scalar.string
                        let tagDescription = String(describing: scalar.tag)
                        if tagDescription.contains("bool") || tagDescription.contains("tag:yaml.org,2002:bool") || stringValue == "true" || stringValue == "false" {
                            array.append(stringValue == "true")
                        } else if tagDescription.contains("int") || tagDescription.contains("tag:yaml.org,2002:int") {
                            array.append(Int(stringValue) ?? stringValue)
                        } else if tagDescription.contains("float") || tagDescription.contains("tag:yaml.org,2002:float") {
                            array.append(Double(stringValue) ?? stringValue)
                        } else {
                            array.append(stringValue)
                        }
                    } else if case .mapping = item {
                        array.append(try nodeToDictionary(item))
                    } else if case .sequence = item {
                        // Nested sequence - flatten or handle as needed
                        array.append(try nodeToDictionary(item))
                    }
                }
                dict[key] = array
            case .alias:
                // Handle aliases by resolving them
                dict[key] = try nodeToDictionary(valueNode)
            }
        }
        return dict
    }
    
    private func parseDictionaryToConfig(_ dict: [String: Any]) throws -> SwiftLintConfiguration {
        var config = SwiftLintConfiguration()
        
        // Parse rules
        if let rulesDict = dict["rules"] as? [String: Any] {
            var rules: [String: RuleConfiguration] = [:]
            for (ruleId, ruleValue) in rulesDict {
                // Check if it's a simple boolean first
                // Handle both Bool and String representations
                var boolValue: Bool?
                if let boolRuleValue = ruleValue as? Bool {
                    boolValue = boolRuleValue
                } else if let str = ruleValue as? String, str == "true" || str == "false" {
                    boolValue = str == "true"
                }
                
                if let boolValue = boolValue {
                    // Simple enabled/disabled
                    rules[ruleId] = RuleConfiguration(enabled: boolValue)
                } else if let ruleDict = ruleValue as? [String: Any] {
                    // Complex configuration with severity/parameters
                    var enabled = true
                    var severity: Severity?
                    var parameters: [String: AnyCodable]?
                    
                    // Parse severity
                    if let severityStr = ruleDict["severity"] as? String {
                        severity = Severity(rawValue: severityStr)
                    }
                    
                    // Parse enabled (might be explicit or implicit)
                    // Handle both Bool and String representations
                    if let enabledValue = ruleDict["enabled"] as? Bool {
                        enabled = enabledValue
                    } else if let enabledStr = ruleDict["enabled"] as? String {
                        enabled = enabledStr.lowercased() == "true"
                    }
                    
                    // Parse parameters (everything else)
                    var params: [String: AnyCodable] = [:]
                    for (paramKey, paramValue) in ruleDict {
                        if paramKey != "severity" && paramKey != "enabled" {
                            params[paramKey] = AnyCodable(paramValue)
                        }
                    }
                    if !params.isEmpty {
                        parameters = params
                    }
                    
                    rules[ruleId] = RuleConfiguration(
                        enabled: enabled,
                        severity: severity,
                        parameters: parameters
                    )
                }
            }
            config.rules = rules
        }
        
        // Parse other fields
        if let included = dict["included"] as? [String] {
            config.included = included
        }
        if let excluded = dict["excluded"] as? [String] {
            config.excluded = excluded
        }
        if let reporter = dict["reporter"] as? String {
            config.reporter = reporter
        }
        
        return config
    }
    
    private func configToDictionary(_ config: YAMLConfig) -> [String: Any] {
        var dict: [String: Any] = [:]
        
        // Add rules
        if !config.rules.isEmpty {
            var rulesDict: [String: Any] = [:]
            for (ruleId, ruleConfig) in config.rules {
                // Check if this is a simple boolean rule (no severity, no parameters, enabled=true)
                if ruleConfig.severity == nil && ruleConfig.parameters == nil && ruleConfig.enabled {
                    // Simple boolean - just enabled
                    rulesDict[ruleId] = true
                } else if ruleConfig.severity == nil && ruleConfig.parameters == nil && !ruleConfig.enabled {
                    // Simple boolean - just disabled
                    rulesDict[ruleId] = false
                } else {
                    // Complex configuration with severity and/or parameters
                    var ruleDict: [String: Any] = [:]
                    if let severity = ruleConfig.severity {
                        ruleDict["severity"] = severity.rawValue
                    }
                    if let parameters = ruleConfig.parameters {
                        for (key, value) in parameters {
                            ruleDict[key] = value.value
                        }
                    }
                    // Always include enabled if it's false
                    // SwiftLint treats enabled=true as default, so we only need to specify if false
                    if !ruleConfig.enabled {
                        ruleDict["enabled"] = false
                    }
                    rulesDict[ruleId] = ruleDict
                }
            }
            dict["rules"] = rulesDict
        }
        
        // Add other fields
        if let included = config.included {
            dict["included"] = included
        }
        if let excluded = config.excluded {
            dict["excluded"] = excluded
        }
        if let reporter = config.reporter {
            dict["reporter"] = reporter
        }
        
        return dict
    }
    
    // MARK: - Comment Preservation
    
    private func extractComments(from content: String) {
        let lines = content.components(separatedBy: .newlines)
        var currentKey: String?
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check for comment
            if trimmed.hasPrefix("#") {
                let comment = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                
                // Try to associate with previous or next key
                if let key = currentKey {
                    currentConfig.comments[key] = comment
                } else if index < lines.count - 1 {
                    // Look ahead for key
                    let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                    if let key = extractKey(from: nextLine) {
                        currentConfig.comments[key] = comment
                    }
                }
            } else if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                // Extract key from this line
                if let key = extractKey(from: line) {
                    currentKey = key
                }
            }
        }
    }
    
    private func extractKey(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Match YAML key pattern: "key:" or "  key:"
        if let colonIndex = trimmed.firstIndex(of: ":") {
            let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                return key
            }
        }
        
        return nil
    }
    
    private func extractKeyOrder(from content: String) {
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                if let key = extractKey(from: line) {
                    if !currentConfig.keyOrder.contains(key) {
                        currentConfig.keyOrder.append(key)
                    }
                }
            }
        }
    }
    
    private func reinsertComments(into yaml: String, config: YAMLConfig) -> String {
        // Basic implementation: append comments at the end
        // More sophisticated comment preservation can be added later
        var result = yaml
        
        if !config.comments.isEmpty {
            result += "\n\n# Preserved comments:\n"
            for (key, comment) in config.comments.sorted(by: { $0.key < $1.key }) {
                result += "# \(key): \(comment)\n"
            }
        }
        
        return result
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

