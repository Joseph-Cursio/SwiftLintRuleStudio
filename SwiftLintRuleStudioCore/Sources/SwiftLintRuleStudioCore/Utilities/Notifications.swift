//
//  Notifications.swift
//  SwiftLintRuleStudio
//
//  App-wide notification names
//

import Foundation

extension Notification.Name {
    /// Posted when a rule configuration is saved
    public static let ruleConfigurationDidChange = Notification.Name("ruleConfigurationDidChange")

    /// Posted when workspace changes
    public static let workspaceDidChange = Notification.Name("workspaceDidChange")

    /// Posted when a configuration version is restored from backup
    public static let configurationDidRestore = Notification.Name("configurationDidRestore")

    /// Posted when the user requests opening a workspace (e.g. via File > Open Workspace… menu)
    public static let openWorkspaceRequested = Notification.Name("OpenWorkspaceRequested")

    /// Posted when the user requests opening a recent workspace (e.g. via dock menu).
    /// userInfo key "url" contains the workspace URL.
    public static let openRecentWorkspaceRequested = Notification.Name("OpenRecentWorkspaceRequested")

    /// Posted when the user requests toggling the detail panel (View menu)
    public static let toggleDetailPanelRequested = Notification.Name("ToggleDetailPanelRequested")

    /// Posted when the user requests simulating impact for a rule (context menu)
    public static let simulateImpactRequested = Notification.Name("SimulateImpactRequested")

    /// Posted when the violation inspector should refresh its data
    public static let violationInspectorRefreshRequested = Notification.Name("ViolationInspectorRefreshRequested")

    /// Posted when the user requests saving configuration changes (e.g. via File > Save menu)
    public static let saveConfigurationRequested = Notification.Name("SaveConfigurationRequested")
}
