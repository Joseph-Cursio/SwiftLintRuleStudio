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
}


