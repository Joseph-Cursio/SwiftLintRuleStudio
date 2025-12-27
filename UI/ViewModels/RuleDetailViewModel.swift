//
//  RuleDetailViewModel.swift
//  SwiftLintRuleStudio
//
//  ViewModel for managing rule configuration and persistence
//

import Foundation
import Combine

@MainActor
class RuleDetailViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isEnabled: Bool
    @Published var severity: Severity?
    @Published var isSaving: Bool = false
    @Published var saveError: Error?
    @Published var showDiffPreview: Bool = false
    @Published var pendingChanges: PendingRuleChanges?
    
    // MARK: - Properties
    
    let rule: Rule
    var yamlEngine: YAMLConfigurationEngine?
    var workspaceManager: WorkspaceManager?
    
    // Track original state to detect changes
    private var originalEnabled: Bool
    private var originalSeverity: Severity?
    
    // MARK: - Initialization
    
    init(rule: Rule, yamlEngine: YAMLConfigurationEngine? = nil, workspaceManager: WorkspaceManager? = nil) {
        self.rule = rule
        self.yamlEngine = yamlEngine
        self.workspaceManager = workspaceManager
        
        // Initialize from rule's current state
        self.isEnabled = rule.isEnabled
        self.severity = rule.severity
        self.originalEnabled = rule.isEnabled
        self.originalSeverity = rule.severity
    }
    
    // MARK: - Public Methods
    
    /// Load current configuration from workspace
    func loadConfiguration() throws {
        guard let yamlEngine = yamlEngine else { return }
        
        // Load current config
        try yamlEngine.load()
        let config = yamlEngine.getConfig()
        
        // Update local state from config
        if let ruleConfig = config.rules[rule.id] {
            self.isEnabled = ruleConfig.enabled
            self.severity = ruleConfig.severity
        } else {
            // Rule not in config - check if it's opt-in or default
            // Default rules are enabled by default, opt-in rules are disabled
            self.isEnabled = !rule.isOptIn
            // Don't set severity if rule is not in config - keep it as nil
            // Only set default severity if rule has one
            self.severity = rule.defaultSeverity
        }
        
        // Update original state
        self.originalEnabled = self.isEnabled
        self.originalSeverity = self.severity
    }
    
    /// Update enabled state
    func updateEnabled(_ enabled: Bool) {
        isEnabled = enabled
        updatePendingChanges()
    }
    
    /// Update severity
    func updateSeverity(_ newSeverity: Severity) {
        severity = newSeverity
        updatePendingChanges()
    }
    
    /// Generate diff for pending changes
    func generateDiff() -> YAMLConfigurationEngine.ConfigDiff? {
        guard let yamlEngine = yamlEngine else { return nil }
        
        do {
            try yamlEngine.load()
            let currentConfig = yamlEngine.getConfig()
            var proposedConfig = currentConfig
            
            // Apply current state changes
            if isEnabled {
                // Enable rule
                if var existing = proposedConfig.rules[rule.id] {
                    existing.enabled = true
                    existing.severity = severity
                    proposedConfig.rules[rule.id] = existing
                } else {
                    // New rule configuration
                    proposedConfig.rules[rule.id] = RuleConfiguration(
                        enabled: true,
                        severity: severity
                    )
                }
            } else {
                // Disable rule
                if var existing = proposedConfig.rules[rule.id] {
                    existing.enabled = false
                    proposedConfig.rules[rule.id] = existing
                } else {
                    // Rule not in config, add it as disabled
                    proposedConfig.rules[rule.id] = RuleConfiguration(enabled: false)
                }
            }
            
            return yamlEngine.generateDiff(proposedConfig: proposedConfig)
        } catch {
            saveError = error
            return nil
        }
    }
    
    /// Save configuration changes
    func saveConfiguration() throws {
        guard let yamlEngine = yamlEngine else {
            throw RuleConfigurationError.noWorkspace
        }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            // Load current config
            try yamlEngine.load()
            var config = yamlEngine.getConfig()
            
            // Apply changes
            if isEnabled {
                // Enable rule
                var ruleConfig = config.rules[rule.id] ?? RuleConfiguration(enabled: true)
                ruleConfig.enabled = true
                if let sev = severity {
                    ruleConfig.severity = sev
                }
                config.rules[rule.id] = ruleConfig
            } else {
                // Disable rule - set enabled: false (keep in config to explicitly disable)
                var ruleConfig = config.rules[rule.id] ?? RuleConfiguration(enabled: false)
                ruleConfig.enabled = false
                config.rules[rule.id] = ruleConfig
            }
            
            // Validate before saving
            try yamlEngine.validate(config)
            
            // Save to file
            try yamlEngine.save(config: config, createBackup: true)
            
            // Update original state to reflect saved changes
            originalEnabled = isEnabled
            originalSeverity = severity
            
            // Clear pending changes
            pendingChanges = nil
            saveError = nil
            
            // Post notification that config was saved (for RuleRegistry to refresh if needed)
            NotificationCenter.default.post(
                name: .ruleConfigurationDidChange,
                object: nil,
                userInfo: ["ruleId": rule.id]
            )
        } catch {
            saveError = error
            throw error
        }
    }
    
    /// Show diff preview
    func showPreview() {
        updatePendingChanges()
        showDiffPreview = true
    }
    
    /// Cancel pending changes
    func cancelChanges() {
        // Reload from config
        try? loadConfiguration()
        pendingChanges = nil
    }
    
    // MARK: - Private Methods
    
    private func updatePendingChanges() {
        // Check if there are actual changes from original state
        if isEnabled != originalEnabled || severity != originalSeverity {
            pendingChanges = PendingRuleChanges(
                enabled: isEnabled,
                severity: severity
            )
        } else {
            pendingChanges = nil
        }
    }
}

// MARK: - Supporting Types

struct PendingRuleChanges {
    let enabled: Bool?
    let severity: Severity?
}

enum RuleConfigurationError: LocalizedError {
    case noWorkspace
    case configLoadFailed
    case saveFailed
    
    var errorDescription: String? {
        switch self {
        case .noWorkspace:
            return "No workspace is open. Please open a workspace to configure rules."
        case .configLoadFailed:
            return "Failed to load configuration file."
        case .saveFailed:
            return "Failed to save configuration changes."
        }
    }
}

