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
    @Published var parameterValues: [String: AnyCodable] = [:]
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
    private var originalParameters: [String: AnyCodable]?
    
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
        self.originalParameters = rule.configuredParameters
        if let configured = rule.configuredParameters {
            self.parameterValues = configured
        }
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
            self.severity = ruleConfig.severity
            if rule.isOptIn {
                self.isEnabled = ruleConfig.enabled
                    && (config.optInRules?.contains(rule.id) ?? false)
            } else {
                self.isEnabled = ruleConfig.enabled
            }
        } else if let onlyRules = config.onlyRules {
            self.isEnabled = onlyRules.contains(rule.id)
            self.severity = rule.defaultSeverity
        } else if config.disabledRules?.contains(rule.id) == true {
            self.isEnabled = false
            self.severity = rule.defaultSeverity
        } else if rule.isOptIn {
            if let optInRules = config.optInRules {
                self.isEnabled = optInRules.contains(rule.id)
            } else {
                self.isEnabled = false
            }
            self.severity = rule.defaultSeverity
        } else {
            // Rule not in config - check if it's opt-in or default
            // Default rules are enabled by default, opt-in rules are disabled
            self.isEnabled = !rule.isOptIn
            // Don't set severity if rule is not in config - keep it as nil
            // Only set default severity if rule has one
            self.severity = rule.defaultSeverity
        }
        
        // Load parameter values from config
        if let ruleConfig = config.rules[rule.id],
           let params = ruleConfig.parameters {
            self.parameterValues = params
        } else {
            // Fall back to defaults from rule definition
            self.parameterValues = defaultParameterValues()
        }

        // Update original state
        self.originalEnabled = self.isEnabled
        self.originalSeverity = self.severity
        self.originalParameters = self.parameterValues.isEmpty ? nil : self.parameterValues
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

    /// Update a single parameter value
    func updateParameter(_ name: String, value: AnyCodable) {
        parameterValues[name] = value
        updatePendingChanges()
    }

    /// Get default parameter values from rule definition
    func defaultParameterValues() -> [String: AnyCodable] {
        guard let params = rule.parameters else { return [:] }
        var defaults: [String: AnyCodable] = [:]
        for param in params {
            defaults[param.name] = param.defaultValue
        }
        return defaults
    }
    
    /// Generate diff for pending changes
    func generateDiff() -> YAMLConfigurationEngine.ConfigDiff? {
        guard let yamlEngine = yamlEngine else { return nil }
        
        do {
            try yamlEngine.load()
            let currentConfig = yamlEngine.getConfig()
            var proposedConfig = currentConfig
            
            // Apply current state changes
            let params = parameterValues.isEmpty ? nil : parameterValues
            if isEnabled {
                // Enable rule
                if var existing = proposedConfig.rules[rule.id] {
                    existing.enabled = true
                    existing.severity = severity
                    existing.parameters = params
                    proposedConfig.rules[rule.id] = existing
                } else {
                    // New rule configuration
                    proposedConfig.rules[rule.id] = RuleConfiguration(
                        enabled: true,
                        severity: severity,
                        parameters: params
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
            try yamlEngine.load()
            var config = yamlEngine.getConfig()
            applyRuleChanges(to: &config)
            try yamlEngine.validate(config)
            try yamlEngine.save(config: config, createBackup: true)
            finalizeSaveSuccess()
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
        let hasParameterChanges = parametersHaveChanged()
        // Check if there are actual changes from original state
        if isEnabled != originalEnabled || severity != originalSeverity || hasParameterChanges {
            let currentParams = parameterValues.isEmpty ? nil : parameterValues
            pendingChanges = PendingRuleChanges(
                enabled: isEnabled,
                severity: severity,
                parameters: currentParams
            )
        } else {
            pendingChanges = nil
        }
    }

    private func parametersHaveChanged() -> Bool {
        let currentParams = parameterValues.isEmpty ? nil : parameterValues
        if currentParams == nil && originalParameters == nil { return false }
        guard let current = currentParams, let original = originalParameters else { return true }
        if current.count != original.count { return true }
        for (key, value) in current {
            guard let originalValue = original[key] else { return true }
            if value != originalValue { return true }
        }
        return false
    }

    private func applyRuleChanges(to config: inout YAMLConfigurationEngine.YAMLConfig) {
        if isEnabled {
            applyEnabledRule(to: &config)
        } else {
            applyDisabledRule(to: &config)
        }
    }

    private func applyEnabledRule(to config: inout YAMLConfigurationEngine.YAMLConfig) {
        var ruleConfig = config.rules[rule.id] ?? RuleConfiguration(enabled: true)
        ruleConfig.enabled = true
        if let sev = severity {
            ruleConfig.severity = sev
        }
        if !parameterValues.isEmpty {
            ruleConfig.parameters = parameterValues
        }
        config.rules[rule.id] = ruleConfig
        addOptInRuleIfNeeded(to: &config)
        removeDisabledRuleIfPresent(from: &config)
        addOnlyRuleIfNeeded(to: &config)
    }

    private func applyDisabledRule(to config: inout YAMLConfigurationEngine.YAMLConfig) {
        var ruleConfig = config.rules[rule.id] ?? RuleConfiguration(enabled: false)
        ruleConfig.enabled = false
        config.rules[rule.id] = ruleConfig
        removeOptInRuleIfPresent(from: &config)
        removeOnlyRuleIfPresent(from: &config)
    }

    private func addOptInRuleIfNeeded(to config: inout YAMLConfigurationEngine.YAMLConfig) {
        guard rule.isOptIn else { return }
        var optInRules = config.optInRules ?? []
        if !optInRules.contains(rule.id) {
            optInRules.append(rule.id)
            config.optInRules = optInRules
        }
    }

    private func removeOptInRuleIfPresent(from config: inout YAMLConfigurationEngine.YAMLConfig) {
        guard rule.isOptIn, var optInRules = config.optInRules else { return }
        optInRules.removeAll { $0 == rule.id }
        config.optInRules = optInRules.isEmpty ? nil : optInRules
    }

    private func removeDisabledRuleIfPresent(from config: inout YAMLConfigurationEngine.YAMLConfig) {
        guard var disabledRules = config.disabledRules else { return }
        disabledRules.removeAll { $0 == rule.id }
        config.disabledRules = disabledRules.isEmpty ? nil : disabledRules
    }

    private func addOnlyRuleIfNeeded(to config: inout YAMLConfigurationEngine.YAMLConfig) {
        guard var onlyRules = config.onlyRules else { return }
        if !onlyRules.contains(rule.id) {
            onlyRules.append(rule.id)
            config.onlyRules = onlyRules
        }
    }

    private func removeOnlyRuleIfPresent(from config: inout YAMLConfigurationEngine.YAMLConfig) {
        guard var onlyRules = config.onlyRules else { return }
        onlyRules.removeAll { $0 == rule.id }
        config.onlyRules = onlyRules.isEmpty ? nil : onlyRules
    }

    private func finalizeSaveSuccess() {
        originalEnabled = isEnabled
        originalSeverity = severity
        originalParameters = parameterValues.isEmpty ? nil : parameterValues
        pendingChanges = nil
        saveError = nil
        NotificationCenter.default.post(
            name: .ruleConfigurationDidChange,
            object: nil,
            userInfo: ["ruleId": rule.id]
        )
    }
}

// MARK: - Supporting Types

struct PendingRuleChanges {
    let enabled: Bool?
    let severity: Severity?
    var parameters: [String: AnyCodable]?
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
