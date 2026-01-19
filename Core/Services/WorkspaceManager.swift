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
    
    @Published private(set) var currentWorkspace: Workspace?
    @Published private(set) var recentWorkspaces: [Workspace] = []
    @Published private(set) var configFileMissing: Bool = false
    
    private let recentWorkspacesKey = "SwiftLintRuleStudio.recentWorkspaces"
    private let maxRecentWorkspaces = 10
    private let userDefaults: UserDefaults
    
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
    
    /// Validate that a directory is a valid Swift project workspace
    private func validateSwiftWorkspace(at url: URL) throws {
        let path = url.path
        let indicators = try scanTopLevelIndicators(at: url)
        if indicators.hasProjectMarker {
            return
        }

        let hasSwiftFiles = indicators.hasSwiftFiles || hasSwiftFilesWithinDepth(
            at: url,
            rootPath: path,
            maxDepth: 3
        )
        if !hasSwiftFiles {
            throw WorkspaceError.notASwiftProject(directory: url.lastPathComponent)
        }
    }

    private struct WorkspaceIndicators {
        let hasProjectMarker: Bool
        let hasSwiftFiles: Bool
    }

    private func scanTopLevelIndicators(at url: URL) throws -> WorkspaceIndicators {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]
            )
            var hasSwiftFiles = false
            var hasProjectMarker = false

            for item in contents {
                if isProjectMarker(item) {
                    hasProjectMarker = true
                }
                if item.pathExtension.lowercased() == "swift" {
                    hasSwiftFiles = true
                }
            }

            return WorkspaceIndicators(hasProjectMarker: hasProjectMarker, hasSwiftFiles: hasSwiftFiles)
        } catch {
            throw WorkspaceError.accessDenied
        }
    }

    private func isProjectMarker(_ url: URL) -> Bool {
        let itemName = url.lastPathComponent
        if itemName.hasSuffix(".xcodeproj") || itemName.hasSuffix(".xcworkspace") {
            return true
        }
        return itemName == "Package.swift" || itemName == ".swiftpm"
    }

    private func hasSwiftFilesWithinDepth(at url: URL, rootPath: String, maxDepth: Int) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return false
        }

        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(of: rootPath + "/", with: "")
            let depth = relativePath.components(separatedBy: "/").count

            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            if shouldSkipWorkspaceScan(path: fileURL.path) {
                enumerator.skipDescendants()
                continue
            }

            if fileURL.pathExtension.lowercased() == "swift" {
                return true
            }
        }

        return false
    }

    private func shouldSkipWorkspaceScan(path: String) -> Bool {
        if path.contains("/.build/") ||
            path.contains("/Pods/") ||
            path.contains("/node_modules/") ||
            path.contains("/.git/") {
            return true
        }
        return false
    }
    
    /// Close the current workspace
    func closeWorkspace() {
        currentWorkspace = nil
        configFileMissing = false
    }
    
    // MARK: - Config File Management
    
    /// Check if SwiftLint config file exists for current workspace
    func checkConfigFileExists() {
        guard let workspace = currentWorkspace else {
            configFileMissing = false
            return
        }
        
        let configPath = workspace.configPath ?? workspace.path.appendingPathComponent(".swiftlint.yml")
        configFileMissing = !FileManager.default.fileExists(atPath: configPath.path)
    }
    
    /// Create a default SwiftLint configuration file for the current workspace
    /// - Returns: URL of the created config file, or nil if creation failed
    @discardableResult
    func createDefaultConfigFile() throws -> URL? {
        guard let workspace = currentWorkspace else {
            throw WorkspaceError.invalidPath
        }
        
        let configPath = workspace.path.appendingPathComponent(".swiftlint.yml")
        
        // Check if file already exists
        if FileManager.default.fileExists(atPath: configPath.path) {
            return configPath
        }
        
        // Create default configuration content
        let defaultConfig = """
        # SwiftLint Configuration
        # This configuration follows best practices for excluding third-party code
        # and setting reasonable defaults for a Swift project.
        
        # Exclude common build and dependency directories
        excluded:
          - .build                    # Swift Package Manager dependencies
          - Pods                      # CocoaPods dependencies
          - .git                      # Git metadata
          - DerivedData               # Xcode build artifacts
          - .swiftpm                  # Swift Package Manager metadata
          - xcuserdata                # Xcode user-specific data
          - .xcode                    # Xcode project files
        
        # Disable rules that are too strict for development
        disabled_rules:
          - todo                      # Allow TODO comments during development
          - trailing_whitespace       # Can be handled by Xcode
        
        # Opt-in rules (enable specific rules that are valuable)
        opt_in_rules:
          - empty_count               # Prefer isEmpty over count == 0
          - empty_string              # Prefer isEmpty over == ""
          - first_where               # Prefer first(where:) over filter.first
          - force_unwrapping          # Warn about force unwraps
          - implicitly_unwrapped_optional  # Warn about IUOs
          - overridden_super_call     # Ensure super calls in overrides
          - prohibited_super_call    # Prevent incorrect super calls
          - redundant_nil_coalescing  # Remove redundant ?? nil
          - single_test_class         # One test class per file
          - unneeded_parentheses_in_closure_argument  # Clean closure syntax
          - vertical_parameter_alignment_on_call  # Align parameters
        
        # Rule configurations
        line_length:
          warning: 120
          error: 150
          ignores_function_declarations: true
          ignores_comments: true
          ignores_urls: true
        
        file_length:
          warning: 500
          error: 1000
          ignore_comment_only_lines: true
        
        function_body_length:
          warning: 50
          error: 100
        
        function_parameter_count:
          warning: 5
          error: 8
        
        type_body_length:
          warning: 300
          error: 500
        
        cyclomatic_complexity:
          warning: 10
          error: 20
        
        nesting:
          type_level: 2
          function_level: 3
        
        # Reporter type (xcode, json, csv, checkstyle, junit, html, emoji, sonarqube, markdown)
        reporter: "xcode"
        
        """
        
        // Write the config file
        try defaultConfig.write(to: configPath, atomically: true, encoding: .utf8)
        
        // Update workspace config path
        var updatedWorkspace = workspace
        updatedWorkspace.configPath = configPath
        currentWorkspace = updatedWorkspace
        
        // Update config file missing status
        configFileMissing = false
        
        return configPath
    }
    
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
    
    // MARK: - Recent Workspaces Management
    
    private func addToRecentWorkspaces(_ workspace: Workspace) {
        // Remove if already exists
        recentWorkspaces.removeAll { $0.path == workspace.path }
        
        // Add to beginning
        recentWorkspaces.insert(workspace, at: 0)
        
        // Limit to max count
        if recentWorkspaces.count > maxRecentWorkspaces {
            recentWorkspaces = Array(recentWorkspaces.prefix(maxRecentWorkspaces))
        }
        
        saveRecentWorkspaces()
    }
    
    // MARK: - Persistence
    
    private func loadRecentWorkspaces() {
        guard let data = userDefaults.data(forKey: recentWorkspacesKey),
              let decoded = try? JSONDecoder().decode([WorkspaceData].self, from: data) else {
            return
        }
        
        // Filter out workspaces that no longer exist
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
        
        // Save back in case some were filtered out
        saveRecentWorkspaces()
    }
    
    private func saveRecentWorkspaces() {
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
    
    // MARK: - Helper Types
    
    private struct WorkspaceData: Codable {
        let id: UUID
        let path: String
        let name: String
        let configPath: String?
        let lastAnalyzed: Date?
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

