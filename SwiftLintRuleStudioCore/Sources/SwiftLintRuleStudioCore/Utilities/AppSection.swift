//
//  AppSection.swift
//  SwiftLintRuleStudio
//
//  Navigation section identifiers used throughout the app
//

public enum AppSection: Hashable, Sendable, CaseIterable {
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
    case configMap

    /// The name shown for this section wherever it is offered as a destination.
    ///
    /// Lives on the enum so a menu can be derived from `allCases` rather than transcribed. The
    /// title menu was transcribed, and had drifted: it listed eleven of the twelve sections and
    /// silently omitted Config Map, which was reachable only from the sidebar.
    public var title: String {
        switch self {
        case .rules: return "Rules"
        case .violations: return "Enabled Rule Violations"
        case .exportReport: return "Export Report"
        case .dashboard: return "Dashboard"
        case .ruleAudit: return "Disabled Rule Audit"
        case .versionHistory: return "Version History"
        case .compareConfigs: return "Compare Configs"
        case .versionCheck: return "Version Check"
        case .importConfig: return "Import Config"
        case .branchDiff: return "Branch Diff"
        case .migration: return "Migration"
        case .configMap: return "Config Map"
        }
    }
}
