//
//  ConfigRuleListsProblem.swift
//  SwiftLintRuleStudio
//
//  What is wrong with a configuration's rule lists, as SwiftLint would see it.
//

import Foundation

/// A rule-list combination SwiftLint mishandles, worth a warning in the app.
public enum ConfigRuleListsProblem: Equatable, Sendable {
    /// `only_rules` beside `opt_in_rules` or `disabled_rules`. SwiftLint ignores the whole
    /// file — `included`, `excluded` and every rule setting with it — and runs its default
    /// configuration instead (issue #83).
    case onlyRulesConflict
    /// Ids listed under both `only_rules` and `analyzer_rules`. They run, but SwiftLint
    /// warns that each is listed twice.
    case analyzerRulesInOnlyRules([String])

    /// The problem with `config`'s rule lists, or nil when SwiftLint reads them cleanly. A
    /// conflict outranks duplicates; the repair fixes both.
    public init?(_ config: YAMLConfigurationEngine.YAMLConfig) {
        if config.hasOnlyRulesConflict {
            self = .onlyRulesConflict
            return
        }
        let duplicated = config.rulesInOnlyAndAnalyzerRules
        guard !duplicated.isEmpty else { return nil }
        self = .analyzerRulesInOnlyRules(duplicated)
    }
}
