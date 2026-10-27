//
//  SimulationWorkspace+OnlyRule.swift
//  SwiftLintRuleStudio
//
//  Which rules a simulation lints alone, as `swiftlint lint --only-rule` does, and how the mirror's
//  configs say for such a lint what they say for a lint of every rule.
//

import Foundation

extension SimulationWorkspace {

    /// The rule to lint alone (`--only-rule`) when measuring `ruleId`, or nil when its count
    /// needs every rule the configs enable.
    ///
    /// A rule's violations don't depend on which other rules run, and `--only-rule` keeps what
    /// the configs say about it: its settings, and the nested configs that disable it. So most
    /// rules are linted alone, which on a large workspace is many times faster. The exceptions:
    /// - `superfluous_disable_command` reports disable commands for rules that ran and found
    ///   nothing, so it needs them running.
    /// - `custom_rules` reports under each custom rule's own name, and `--only-rule` keeps only
    ///   the custom rules it names, so linted alone it finds nothing; a custom rule linted alone
    ///   loses whatever the configs say about the others.
    /// - A nested config SwiftLint rejects for listing `only_rules` beside `disabled_rules` or
    ///   `opt_in_rules`, which ``applyRule(_:isOptIn:isAnalyzer:parameterOverrides:)`` could
    ///   only rewrite into one SwiftLint accepts; see ``keepsOff(_:_:)``.
    func onlyRule(for ruleId: String) -> String? {
        guard ruleId != "superfluous_disable_command",
              ruleId != "custom_rules",
              !customRuleIds.contains(ruleId) else {
            return nil
        }
        let hasRejectedOnlyRules = configs.contains { entry in
            let config = entry.original
            return !entry.isRootConfiguration && config.onlyRules?.isEmpty == false
                && (config.disabledRules?.isEmpty == false || config.optInRules?.isEmpty == false)
        }
        return hasRejectedOnlyRules ? nil : ruleId
    }

    /// Whether `entry` is a nested config whose `only_rules` leaves `ruleId` out, under any of
    /// its names, which keeps the rule off beneath it.
    ///
    /// `--only-rule` overrides a nested `only_rules`, so linted alone the rule would run there.
    /// It honours a nested `disabled_rules`, so for a lint of the rule alone such a config is
    /// written as one that disables it: beneath it no rule runs, which is what a lint of every
    /// rule counts for this one. Its other settings, the paths it includes and excludes among
    /// them, stay as they are.
    func keepsOff(_ ruleId: String, _ entry: ConfigEntry) -> Bool {
        guard !entry.isRootConfiguration, let only = entry.original.onlyRules, !only.isEmpty else {
            return false
        }
        let rule = SwiftLintDeprecations.currentName(of: ruleId)
        return !(only + (entry.original.analyzerRules ?? [])).contains {
            SwiftLintDeprecations.currentName(of: $0) == rule
        }
    }
}
