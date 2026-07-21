//
//  WorkspaceManager.swift
//  SwiftLintRuleStudio
//
//  Service for managing workspace selection and recent workspaces
//

import Foundation
import Observation

// MARK: - Errors

public enum WorkspaceError: LocalizedError, Sendable {
    case notADirectory
    case invalidPath
    case accessDenied
    case notASwiftProject(directory: String)

    public var errorDescription: String? {
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

    public var recoverySuggestion: String? {
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

/// Service for managing workspace selection and history
@MainActor
@Observable
public class WorkspaceManager {

    // MARK: - Properties

    /// The currently active workspace
    public var currentWorkspace: Workspace?
    /// List of recently opened workspaces
    public var recentWorkspaces: [Workspace] = []
    /// Whether the current workspace is missing a `.swiftlint.yml` config file
    public var configFileMissing: Bool = false

    /// UserDefaults key for persisting recent workspaces
    public let recentWorkspacesKey = "SwiftLintRuleStudio.recentWorkspaces"
    /// Maximum number of recent workspaces to persist
    public let maxRecentWorkspaces = 10
    /// The UserDefaults instance used for persistence
    public let userDefaults: UserDefaults

    /// Optional security-scoped bookmark store. Injected by the sandboxed target
    /// so folders can be reopened across launches; `nil` in the non-sandboxed
    /// target, where plain paths suffice.
    private let bookmarkStore: (any SecurityScopedBookmarkStoring)?
    /// The folder whose security scope is currently held open (so it can be
    /// released when the workspace changes or closes).
    private var activeScopedURL: URL?

    // MARK: - Initialization

    /// Initialize the workspace manager with the specified user defaults and an
    /// optional security-scoped bookmark store (sandboxed target only).
    public init(
        userDefaults: UserDefaults = .standard,
        bookmarkStore: (any SecurityScopedBookmarkStoring)? = nil
    ) {
        self.userDefaults = userDefaults
        self.bookmarkStore = bookmarkStore
        loadRecentWorkspaces()
    }

    // MARK: - Security-Scoped Access

    /// Regain (from a stored bookmark) or establish (for a freshly picked folder)
    /// sandbox access to the folder at `url`. A no-op when no bookmark store is
    /// configured (non-sandboxed target).
    ///
    /// The workspace's *identity* stays `url` (the caller keeps using it): a
    /// resolved bookmark may report a symlink-canonicalized path
    /// (`/var` → `/private/var`), but the security scope is granted to the folder
    /// itself, so reads via the original path succeed once the scope is held.
    private func beginAccess(to url: URL) {
        guard let bookmarkStore else { return }
        endAccess()
        if let resolved = bookmarkStore.resolveURL(forPath: url.path) {
            _ = resolved.startAccessingSecurityScopedResource()
            activeScopedURL = resolved
            return
        }
        // Freshly granted URL (e.g. from NSOpenPanel): hold the scope and persist
        // a bookmark, keyed by this path, so the folder can be reopened next launch.
        _ = url.startAccessingSecurityScopedResource()
        activeScopedURL = url
        bookmarkStore.saveBookmark(for: url)
    }

    /// Release the currently held security scope, if any.
    private func endAccess() {
        activeScopedURL?.stopAccessingSecurityScopedResource()
        activeScopedURL = nil
    }

    // MARK: - Workspace Selection

    /// Open a workspace from a file URL
    public func openWorkspace(at url: URL) throws {
        // Resolve sandbox access first (regain via bookmark for a recents reopen,
        // or persist one for a fresh pick). Identity stays `url`; the scope is held
        // on the folder so reads via this path succeed.
        beginAccess(to: url)

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
            updated.lastAnalyzed = Date.now
            recentWorkspaces.insert(updated, at: 0)
            currentWorkspace = updated
            // Persist the reordered list so the "most recent" order survives relaunch;
            // the new-workspace branch persists via addToRecentWorkspaces below.
            saveRecentWorkspaces()
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
    public func closeWorkspace() {
        endAccess()
        currentWorkspace = nil
        configFileMissing = false
    }
}
