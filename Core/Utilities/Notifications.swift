//
//  Notifications.swift
//  SwiftLintRuleStudio
//
//  App-wide notification names
//

import Foundation

extension Notification.Name {
    /// Posted when a rule configuration is saved
    static let ruleConfigurationDidChange = Notification.Name("ruleConfigurationDidChange")
    
    /// Posted when workspace changes
    static let workspaceDidChange = Notification.Name("workspaceDidChange")

    /// Posted when a configuration version is restored from backup
    static let configurationDidRestore = Notification.Name("configurationDidRestore")

    /// Posted when the user requests opening a workspace (e.g. via File > Open Workspace… menu)
    static let openWorkspaceRequested = Notification.Name("OpenWorkspaceRequested")

    /// Posted when the user requests opening a recent workspace (e.g. via dock menu).
    /// userInfo key "url" contains the workspace URL.
    static let openRecentWorkspaceRequested = Notification.Name("OpenRecentWorkspaceRequested")

    /// Posted when the user requests toggling the detail panel (View menu)
    static let toggleDetailPanelRequested = Notification.Name("ToggleDetailPanelRequested")

    /// Posted when the user requests simulating impact for a rule (context menu)
    static let simulateImpactRequested = Notification.Name("SimulateImpactRequested")
}
