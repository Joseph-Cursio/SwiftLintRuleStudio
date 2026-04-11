//
//  AppSection.swift
//  SwiftLintRuleStudio
//
//  Navigation section identifiers used throughout the app
//

public enum AppSection: Hashable, Sendable {
    case rules
    case violations
    case exportReport
    case dashboard
    case ruleAudit
    case versionHistory
    case compareConfigs
    case versionCheck
    case importConfig
    case branchDiff
    case migration
}
