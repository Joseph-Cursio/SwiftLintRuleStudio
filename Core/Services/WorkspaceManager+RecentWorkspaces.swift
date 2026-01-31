//
//  WorkspaceManager+RecentWorkspaces.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

extension WorkspaceManager {
    /// Remove a workspace from recent workspaces
    func removeFromRecentWorkspaces(_ workspace: Workspace) {
        recentWorkspaces.removeAll { $0.id == workspace.id }
        saveRecentWorkspaces()
    }

    /// Clear all recent workspaces
    func clearRecentWorkspaces() {
        recentWorkspaces.removeAll()
        saveRecentWorkspaces()
    }
}

extension WorkspaceManager {
    func addToRecentWorkspaces(_ workspace: Workspace) {
        recentWorkspaces.removeAll { $0.path == workspace.path }
        recentWorkspaces.insert(workspace, at: 0)

        if recentWorkspaces.count > maxRecentWorkspaces {
            recentWorkspaces = Array(recentWorkspaces.prefix(maxRecentWorkspaces))
        }

        saveRecentWorkspaces()
    }
}
