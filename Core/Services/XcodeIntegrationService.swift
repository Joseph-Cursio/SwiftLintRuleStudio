//
//  XcodeIntegrationService.swift
//  SwiftLintRuleStudio
//
//  Service for integrating with Xcode to open files at specific lines
//

import Foundation
import AppKit

/// Service for opening files in Xcode
@MainActor
class XcodeIntegrationService {
    private let workspaceManager: WorkspaceManager
    private var projectCache: [URL: URL] = [:] // Cache workspace -> project mapping
    
    init(workspaceManager: WorkspaceManager) {
        self.workspaceManager = workspaceManager
    }
    
    /// Open a file in Xcode at a specific line and column
    /// - Parameters:
    ///   - path: File path (can be absolute or relative to workspace)
    ///   - line: Line number (1-indexed)
    ///   - column: Optional column number (1-indexed)
    ///   - workspace: Workspace containing the file
    /// - Returns: True if successfully opened, false otherwise
    /// - Throws: XcodeIntegrationError if file cannot be opened
    func openFile(
        at path: String,
        line: Int,
        column: Int?,
        in workspace: Workspace
    ) async throws -> Bool {
        // 1. Resolve file path
        let fileURL = try resolveFilePath(path, in: workspace)
        
        // 2. Validate file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw XcodeIntegrationError.fileNotFound(path: fileURL.path)
        }
        
        // 3. Find associated Xcode project/workspace
        let projectURL = findXcodeProject(for: fileURL, in: workspace)
        
        // 4. Try to open using various methods
        return try await openFileInXcode(
            fileURL: fileURL,
            line: line,
            column: column,
            projectURL: projectURL
        )
    }
    
    /// Resolve a file path (absolute or relative) to a full URL
    private func resolveFilePath(_ path: String, in workspace: Workspace) throws -> URL {
        // If path is already absolute, use it directly
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        
        // Otherwise, resolve relative to workspace root
        return workspace.path.appendingPathComponent(path)
    }
    
    /// Find the closest Xcode project or workspace for a given file
    func findXcodeProject(for fileURL: URL, in workspace: Workspace) -> URL? {
        // Check cache first
        if let cached = projectCache[workspace.path] {
            return cached
        }
        
        // Search for .xcodeproj or .xcworkspace files
        let fileManager = FileManager.default
        var foundProjects: [URL] = []
        
        // Search from file location up to workspace root
        var currentDir = fileURL.deletingLastPathComponent()
        let workspacePath = workspace.path.path
        
        while currentDir.path.hasPrefix(workspacePath) {
            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: currentDir,
                    includingPropertiesForKeys: [.isDirectoryKey]
                )
                
                for item in contents {
                    let name = item.lastPathComponent
                    if name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") {
                        foundProjects.append(item)
                    }
                }
                
                // If we found projects, break (closest ones first)
                if !foundProjects.isEmpty {
                    break
                }
                
                // Move up one directory
                let parent = currentDir.deletingLastPathComponent()
                if parent.path == currentDir.path {
                    break // Reached filesystem root
                }
                currentDir = parent
            } catch {
                break
            }
        }
        
        // Prefer workspace over project, prefer closest
        let workspaceProjects = foundProjects.filter { $0.pathExtension == "xcworkspace" }
        let projectFiles = foundProjects.filter { $0.pathExtension == "xcodeproj" }
        
        let selected: URL?
        if !workspaceProjects.isEmpty {
            selected = workspaceProjects.first
        } else if !projectFiles.isEmpty {
            selected = projectFiles.first
        } else {
            selected = nil
        }
        
        // Cache the result
        if let selected = selected {
            projectCache[workspace.path] = selected
        }
        
        return selected
    }
    
    /// Check if Xcode is installed
    func isXcodeInstalled() -> Bool {
        // Check if Xcode.app exists
        let xcodePath = "/Applications/Xcode.app"
        if FileManager.default.fileExists(atPath: xcodePath) {
            return true
        }
        
        // Check if xcode:// URL scheme is registered
        if let xcodeURL = URL(string: "xcode://") {
            return NSWorkspace.shared.urlForApplication(toOpen: xcodeURL) != nil
        }
        
        return false
    }
    
    /// Open file in Xcode using various fallback methods
    private func openFileInXcode(
        fileURL: URL,
        line: Int,
        column: Int?,
        projectURL: URL?
    ) async throws -> Bool {
        // Method 1: Try xed command line tool first (most reliable)
        // This is preferred because it's more reliable than the URL scheme
        if try await openWithXedCommand(fileURL: fileURL, line: line) {
            return true
        }
        
        // Method 2: Try xcode:// URL scheme as fallback
        if let xcodeURL = generateXcodeURL(fileURL: fileURL, line: line, column: column, projectURL: projectURL) {
            if NSWorkspace.shared.open(xcodeURL) {
                return true
            }
        }
        
        // Method 3: Fallback to opening file in default editor
        if NSWorkspace.shared.open(fileURL) {
            return true
        }
        
        throw XcodeIntegrationError.failedToOpen
    }
    
    /// Generate xcode:// URL for opening file
    private func generateXcodeURL(
        fileURL: URL,
        line: Int,
        column: Int?,
        projectURL: URL?
    ) -> URL? {
        // Use query parameter format which is more reliable and handles special characters
        var components = URLComponents()
        components.scheme = "xcode"
        components.host = "file"
        
        // URL-encode the path properly
        let pathString = fileURL.path
        var queryItems = [
            URLQueryItem(name: "path", value: pathString),
            URLQueryItem(name: "line", value: "\(line)")
        ]
        if let column = column {
            queryItems.append(URLQueryItem(name: "column", value: "\(column)"))
        }
        components.queryItems = queryItems
        
        return components.url
    }
    
    /// Try opening file using xed command line tool
    private func openWithXedCommand(fileURL: URL, line: Int) async throws -> Bool {
        // xed is typically in /usr/bin/xed, but can also be accessed via xcode-select
        let xedPath = "/usr/bin/xed"
        guard FileManager.default.fileExists(atPath: xedPath) else {
            return false
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: xedPath)
        process.arguments = ["--line", "\(line)", fileURL.path]
        process.standardOutput = nil
        process.standardError = nil
        
        do {
            try process.run()
            // Don't wait for exit - xed opens Xcode asynchronously
            // Return true if process started successfully
            return true
        } catch {
            return false
        }
    }
    
    /// Clear project cache (useful when workspace changes)
    func clearCache() {
        projectCache.removeAll()
    }
}

/// Errors that can occur during Xcode integration
enum XcodeIntegrationError: LocalizedError {
    case fileNotFound(path: String)
    case xcodeNotInstalled
    case failedToOpen
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .xcodeNotInstalled:
            return "Xcode is not installed"
        case .failedToOpen:
            return "Failed to open file in Xcode"
        }
    }
}
