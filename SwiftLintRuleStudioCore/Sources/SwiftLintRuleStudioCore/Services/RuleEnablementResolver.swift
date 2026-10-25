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
    /// 1. A non-empty `only_rules:` is an exclusive allowlist. SwiftLint unions it
    ///    with `analyzer_rules:`, and nothing else matters, not even opt-in status.
    ///    An empty `only_rules:` counts as no list at all.
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
    ///
    /// A file SwiftLint rejects — `only_rules:` next to `opt_in_rules:` or
    /// `disabled_rules:` (issue #83) — is resolved as `normalizedRuleLists()` will
    /// repair it. SwiftLint runs its defaults for such a file today, but the app
    /// warns about that separately and refuses to save until it is repaired, so the
    /// toggles show what the repair preview will write rather than flip when it does.
    ///
    /// Each list is read the way SwiftLint reads it, a deprecated alias as its rule:
    /// `disabled_rules: [if_let_shadowing]` turns `shorthand_optional_binding` off.
    nonisolated public static func isRuleEnabled(
        _ rule: Rule,
        config: YAMLConfigurationEngine.YAMLConfig
    ) -> Bool {
        let config = config.normalizedRuleLists()
        let ruleName = SwiftLintDeprecations.currentName(of: rule.id)
        func listed(in list: [String]?) -> Bool {
            list?.contains { SwiftLintDeprecations.currentName(of: $0) == ruleName } == true
        }
        if config.usesOnlyRules {
            return listed(in: config.onlyRules) || listed(in: config.analyzerRules)
        }
        if rule.isAnalyzer {
            if config.rules[rule.id]?.enabled == false {
                return false
            }
            return listed(in: config.analyzerRules)
        }
        if rule.isOptIn {
            if config.rules[rule.id]?.enabled == false {
                return false
            }
            return listed(in: config.optInRules)
        }
        if listed(in: config.disabledRules) {
            return false
        }
        if let ruleConfig = config.rules[rule.id] {
            return ruleConfig.enabled
        }
        return true
    }
}
