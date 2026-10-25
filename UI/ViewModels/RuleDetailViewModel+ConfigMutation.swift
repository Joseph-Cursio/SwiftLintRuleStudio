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
    /// Throws when turning the rule off would empty `only_rules`, which SwiftLint
    /// reads as no list at all — see `YAMLConfig.disableRules(_:kind:)`.
    func applyRuleChanges(to config: inout YAMLConfigurationEngine.YAMLConfig) throws {
        if isEnabled {
            applyEnabledRule(to: &config)
        } else {
            try applyDisabledRule(to: &config)
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
        // The rule lists go through the shared routing, which knows only_rules: this
        // used to add an opt-in rule to opt_in_rules *and* only_rules, the combination
        // SwiftLint rejects (issue #83) — on every save, a parameter-only edit included.
        config.enableRule(rule.id, kind: RuleListKind(rule))
    }

    func applyDisabledRule(to config: inout YAMLConfigurationEngine.YAMLConfig) throws {
        // Opt-in and analyzer rules are disabled by absence from their lists, a
        // default rule by disabled_rules — or, under only_rules, by leaving it.
        try config.disableRule(rule.id, kind: RuleListKind(rule))
        var ruleConfig = config.rules[rule.id] ?? RuleConfiguration(enabled: false)
        ruleConfig.enabled = false
        config.rules[rule.id] = ruleConfig
    }
}
