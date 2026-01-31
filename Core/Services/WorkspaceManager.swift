//
//  WorkspaceManager.swift
//  SwiftLintRuleStudio
//
//  Service for managing workspace selection and recent workspaces
//

import Foundation
import Combine

/// Service for managing workspace selection and history
@MainActor
class WorkspaceManager: ObservableObject {
    
    // MARK: - Properties
    
    @Published var currentWorkspace: Workspace?
    @Published var recentWorkspaces: [Workspace] = []
    @Published var configFileMissing: Bool = false
    
    let recentWorkspacesKey = "SwiftLintRuleStudio.recentWorkspaces"
    let maxRecentWorkspaces = 10
    let userDefaults: UserDefaults
    
    // MARK: - Initialization
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadRecentWorkspaces()
    }
    
    // MARK: - Workspace Selection
    
    /// Open a workspace from a file URL
    func openWorkspace(at url: URL) throws {
        // Validate that the URL is a directory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw WorkspaceError.notADirectory
        }
        
        // Validate that it's a valid Swift project workspace
        try validateSwiftWorkspace(at: url)
        
        // Check if workspace already exists in recent workspaces
        if let existingIndex = recentWorkspaces.firstIndex(where: { $0.path == url }) {
            // Move existing workspace to top
            let existing = recentWorkspaces.remove(at: existingIndex)
            var updated = existing
            updated.lastAnalyzed = Date()
            recentWorkspaces.insert(updated, at: 0)
            currentWorkspace = updated
        } else {
            // Create new workspace
            let workspace = Workspace(path: url)
            currentWorkspace = workspace
            addToRecentWorkspaces(workspace)
        }
        
        // Check if config file exists
        checkConfigFileExists()
    }
    
    /// Close the current workspace
    func closeWorkspace() {
        currentWorkspace = nil
        configFileMissing = false
    }
}

// MARK: - Errors

enum WorkspaceError: LocalizedError {
    case notADirectory
    case invalidPath
    case accessDenied
    case notASwiftProject(directory: String)
    
    var errorDescription: String? {
        switch self {
        case .notADirectory:
            return "The selected path is not a directory. Please select a folder containing your Swift project."
        case .invalidPath:
            return "The selected path is invalid or no longer exists."
        case .accessDenied:
            return "Access to the selected directory was denied. Please check file permissions."
        case .notASwiftProject(let directory):
            return """
            The selected folder "\(directory)" does not appear to be a valid Swift project workspace.
            
            A valid Swift workspace should contain:
            • Swift source files (.swift)
            • An Xcode project (.xcodeproj) or workspace (.xcworkspace)
            • A Package.swift file (for Swift Package Manager projects)
            
            Please select a directory that contains your Swift project files.
            """
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notASwiftProject:
            return "Select a directory containing Swift source files, an Xcode project, or a Package.swift file."
        case .notADirectory:
            return "Make sure you're selecting a folder, not a file."
        case .accessDenied:
            return "Check that you have read permissions for the selected directory."
        case .invalidPath:
            return "The path may have been moved or deleted. Please select a different directory."
        }
    }
}
