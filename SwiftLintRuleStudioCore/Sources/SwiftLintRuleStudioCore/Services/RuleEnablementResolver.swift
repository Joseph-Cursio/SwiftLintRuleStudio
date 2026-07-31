//
//  RuleEnablementResolver.swift
//  SwiftLintRuleStudio
//
//  The single answer to "would SwiftLint run this rule under this config?".
//

import Foundation

/// Resolves whether a rule is active under a given `.swiftlint.yml`.
///
/// This logic previously existed in three places — `RuleRegistry`,
/// `RuleAuditView` and `RuleDetailViewModel` — which had drifted apart: only
/// the audit copy learned to handle analyzer rules, so the Rule Browser
/// reported analyzer rules as enabled even when they were absent from
/// `analyzer_rules:`. Keep the precedence order here and here only.
public enum RuleEnablementResolver {

    /// Whether `rule` is active under `config`, mirroring SwiftLint's own
    /// precedence:
    ///
    /// 1. `only_rules:` is an exclusive allowlist — if present, nothing else
    ///    matters, not even analyzer or opt-in status.
    /// 2. Analyzer rules run only when listed under `analyzer_rules:`. SwiftLint
    ///    also reports them as `opt-in: yes`, so this must be checked *before*
    ///    the opt-in branch or a stray `opt_in_rules:` entry would enable them.
    /// 3. Opt-in rules are off unless listed under `opt_in_rules:`.
    /// 4. `disabled_rules:` turns off an otherwise-default rule.
    /// 5. An explicit entry in the rules mapping supplies its own `enabled` flag.
    /// 6. Everything else — a default rule with no configuration — is on.
    ///
    /// For analyzer and opt-in rules an explicit `enabled: false` in the rules
    /// mapping overrides the list membership, so a rule can be parked without
    /// removing it from `analyzer_rules:`/`opt_in_rules:`.
    nonisolated public static func isRuleEnabled(
        _ rule: Rule,
        config: YAMLConfigurationEngine.YAMLConfig
    ) -> Bool {
        if let onlyRules = config.onlyRules {
            return onlyRules.contains(rule.id)
        }
        if rule.isAnalyzer {
            if config.rules[rule.id]?.enabled == false {
                return false
            }
            return config.analyzerRules?.contains(rule.id) ?? false
        }
        if rule.isOptIn {
            if config.rules[rule.id]?.enabled == false {
                return false
            }
            guard let optInRules = config.optInRules else { return false }
            return optInRules.contains(rule.id)
        }
        if config.disabledRules?.contains(rule.id) == true {
            return false
        }
        if let ruleConfig = config.rules[rule.id] {
            return ruleConfig.enabled
        }
        return true
    }
}
