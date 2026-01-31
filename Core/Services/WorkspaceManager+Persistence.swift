//
//  WorkspaceManager+Persistence.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

private struct WorkspaceData: Codable {
    let id: UUID
    let path: String
    let name: String
    let configPath: String?
    let lastAnalyzed: Date?
}

extension WorkspaceManager {
    func loadRecentWorkspaces() {
        guard let data = userDefaults.data(forKey: recentWorkspacesKey),
              let decoded = try? JSONDecoder().decode([WorkspaceData].self, from: data) else {
            return
        }

        recentWorkspaces = decoded.compactMap { data in
            let url = URL(fileURLWithPath: data.path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }

            var workspace = Workspace(id: data.id, path: url, name: data.name)
            workspace.configPath = data.configPath.map { URL(fileURLWithPath: $0) }
            workspace.lastAnalyzed = data.lastAnalyzed
            return workspace
        }

        saveRecentWorkspaces()
    }
}

extension WorkspaceManager {
    func saveRecentWorkspaces() {
        let data = recentWorkspaces.map { workspace in
            WorkspaceData(
                id: workspace.id,
                path: workspace.path.path,
                name: workspace.name,
                configPath: workspace.configPath?.path,
                lastAnalyzed: workspace.lastAnalyzed
            )
        }

        if let encoded = try? JSONEncoder().encode(data) {
            userDefaults.set(encoded, forKey: recentWorkspacesKey)
        }
    }
}
