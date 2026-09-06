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
    let lastOpened: Date?

    init(id: UUID, path: String, name: String, configPath: String?, lastOpened: Date?) {
        self.id = id
        self.path = path
        self.name = name
        self.configPath = configPath
        self.lastOpened = lastOpened
    }

    /// Includes the key this field was written under before it was renamed.
    private enum CodingKeys: String, CodingKey {
        case id, path, name, configPath, lastOpened
        case lastAnalyzed
    }

    /// Reads `lastOpened`, falling back to whatever was stored under `lastAnalyzed`.
    ///
    /// Carrying the old values forward is not only politeness about someone's stored list: the old
    /// field was written by `openWorkspace(at:)` and by nothing else, so a value stored under
    /// `lastAnalyzed` *was* an open time. The rename is what makes it readable, not a change to
    /// what it holds.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decode(String.self, forKey: .name)
        configPath = try container.decodeIfPresent(String.self, forKey: .configPath)
        lastOpened = try container.decodeIfPresent(Date.self, forKey: .lastOpened)
            ?? container.decodeIfPresent(Date.self, forKey: .lastAnalyzed)
    }

    /// Writes only the current key. The legacy one is read, never written, so a list that has been
    /// saved once stops carrying it.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(configPath, forKey: .configPath)
        try container.encodeIfPresent(lastOpened, forKey: .lastOpened)
    }
}

public extension WorkspaceManager {
    /// Loads recent workspaces from UserDefaults, filtering out deleted directories
    func loadRecentWorkspaces() {
        guard let data = userDefaults.data(forKey: recentWorkspacesKey),
              let decoded = try? JSONDecoder().decode(
                [WorkspaceData].self, from: data
              ) else {
            return
        }

        recentWorkspaces = decoded.compactMap { data in
            let url = URL(fileURLWithPath: data.path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }

            var workspace = Workspace(
                path: url, id: data.id, name: data.name
            )
            workspace.configPath = data.configPath.map {
                URL(fileURLWithPath: $0)
            }
            workspace.lastOpened = data.lastOpened
            return workspace
        }

        saveRecentWorkspaces()
    }

    /// Persists the current recent workspaces list to UserDefaults
    func saveRecentWorkspaces() {
        let data = recentWorkspaces.map { workspace in
            WorkspaceData(
                id: workspace.id,
                path: workspace.path.path,
                name: workspace.name,
                configPath: workspace.configPath?.path,
                lastOpened: workspace.lastOpened
            )
        }

        if let encoded = try? JSONEncoder().encode(data) {
            userDefaults.set(encoded, forKey: recentWorkspacesKey)
        }
    }
}
