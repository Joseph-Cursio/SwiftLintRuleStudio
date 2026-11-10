//
//  RuleListKind.swift
//  SwiftLintRuleStudio
//

import Foundation

/// Which list turns a rule on when a configuration has no `only_rules`.
nonisolated public enum RuleListKind: Sendable, Equatable {
    /// On unless listed under `disabled_rules`.
    case standard
    /// Off unless listed under `opt_in_rules`.
    case optIn
    /// Off unless listed under `analyzer_rules`, and run only by `swiftlint analyze`.
    case analyzer

    /// SwiftLint reports every analyzer rule as opt-in too (`AnalyzerRule` refines
    /// `OptInRule`), so the analyzer flag decides first.
    nonisolated public init(isOptIn: Bool, isAnalyzer: Bool) {
        if isAnalyzer {
            self = .analyzer
        } else if isOptIn {
            self = .optIn
        } else {
            self = .standard
        }
    }

    nonisolated public init(_ rule: Rule) {
        self.init(isOptIn: rule.isOptIn, isAnalyzer: rule.isAnalyzer)
    }
}
