//
//  AppSection.swift
//  SwiftLintRuleStudio
//
//  Navigation section identifiers used throughout the app
//

public enum AppSection: Hashable, Sendable {
    case rules
    case violations
    case dashboard
    case safeRules
    case versionHistory
    case compareConfigs
    case versionCheck
    case importConfig
    case branchDiff
    case migration
}
