//
//  RuleDetailViewModel+ConfigMutation.swift
//  SwiftLintRuleStudio
//
//  Helpers that translate the view-model's in-memory state into the
//  workspace YAML mutations carried out by saveConfiguration().
//

import Foundation
import SwiftLintRuleStudioCore

extension RuleDetailViewModel {
    func applyRuleChanges(to config: inout YAMLConfigurationEngine.YAMLConfig) {
        if isEnabled {
            applyEnabledRule(to: &config)
        } else {
            applyDisabledRule(to: &config)
        }
    }

    func applyEnabledRule(to config: inout YAMLConfigurationEngine.YAMLConfig) {
        var ruleConfig = config.rules[rule.id] ?? RuleConfiguration(enabled: true)
        ruleConfig.enabled = true
        if let sev = severity {
            ruleConfig.severity = sev
        }
        let persistable = parametersToPersist()
        if !persistable.isEmpty {
            ruleConfig.parameters = persistable
        } else {
            // Drop any previously-persisted parameter overrides if the user
            // has reset everything back to defaults.
            ruleConfig.parameters = nil
        }
        config.rules[rule.id] = ruleConfig
        addOptInRuleIfNeeded(to: &config)
        removeDisabledRuleIfPresent(from: &config)
        addOnlyRuleIfNeeded(to: &config)
    }

    func applyDisabledRule(to config: inout YAMLConfigurationEngine.YAMLConfig) {
        var ruleConfig = config.rules[rule.id] ?? RuleConfiguration(enabled: false)
        ruleConfig.enabled = false
        config.rules[rule.id] = ruleConfig
        removeOptInRuleIfPresent(from: &config)
        removeOnlyRuleIfPresent(from: &config)
        addDisabledRuleIfNeeded(to: &config)
    }

    func addDisabledRuleIfNeeded(to config: inout YAMLConfigurationEngine.YAMLConfig) {
        // Opt-in / analyzer rules are disabled by absence from their lists,
        // not by being added to disabled_rules.
        guard !rule.isOptIn && !rule.isAnalyzer else { return }
        var disabledRules = config.disabledRules ?? []
        if !disabledRules.contains(rule.id) {
            disabledRules.append(rule.id)
            config.disabledRules = disabledRules
        }
    }

    func addOptInRuleIfNeeded(to config: inout YAMLConfigurationEngine.YAMLConfig) {
        if rule.isAnalyzer {
            var analyzerRules = config.analyzerRules ?? []
            if !analyzerRules.contains(rule.id) {
                analyzerRules.append(rule.id)
                config.analyzerRules = analyzerRules
            }
            return
        }
        guard rule.isOptIn else { return }
        var optInRules = config.optInRules ?? []
        if !optInRules.contains(rule.id) {
            optInRules.append(rule.id)
            config.optInRules = optInRules
        }
    }

    func removeOptInRuleIfPresent(from config: inout YAMLConfigurationEngine.YAMLConfig) {
        if rule.isAnalyzer, var analyzerRules = config.analyzerRules {
            analyzerRules.removeAll { $0 == rule.id }
            config.analyzerRules = analyzerRules.isEmpty ? nil : analyzerRules
        }
        guard rule.isOptIn, var optInRules = config.optInRules else { return }
        optInRules.removeAll { $0 == rule.id }
        config.optInRules = optInRules.isEmpty ? nil : optInRules
    }

    func removeDisabledRuleIfPresent(from config: inout YAMLConfigurationEngine.YAMLConfig) {
        guard var disabledRules = config.disabledRules else { return }
        disabledRules.removeAll { $0 == rule.id }
        config.disabledRules = disabledRules.isEmpty ? nil : disabledRules
    }

    func addOnlyRuleIfNeeded(to config: inout YAMLConfigurationEngine.YAMLConfig) {
        guard var onlyRules = config.onlyRules else { return }
        if !onlyRules.contains(rule.id) {
            onlyRules.append(rule.id)
            config.onlyRules = onlyRules
        }
    }

    func removeOnlyRuleIfPresent(from config: inout YAMLConfigurationEngine.YAMLConfig) {
        guard var onlyRules = config.onlyRules else { return }
        onlyRules.removeAll { $0 == rule.id }
        config.onlyRules = onlyRules.isEmpty ? nil : onlyRules
    }
}
