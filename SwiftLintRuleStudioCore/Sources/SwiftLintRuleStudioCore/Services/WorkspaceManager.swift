//
//  WorkspaceManager.swift
//  SwiftLintRuleStudio
//
//  Service for managing workspace selection and recent workspaces
//

import Foundation
import Observation
import SwiftLintCLISeam

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
    /// What is wrong with the rule lists in the current workspace's `.swiftlint.yml`, if
    /// anything. Refreshed by `checkConfigRuleLists()`.
    public var configRuleListsProblem: ConfigRuleListsProblem?

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
    /// Where the workspace's security scope is held, so that a lint still reading the
    /// workspace keeps it open after the workspace changes or closes.
    private let securityScopes: HeldSecurityScopes
    /// The current workspace's security scope, if one is held open (so it can be
    /// released when the workspace changes or closes).
    private var activeScope: HeldSecurityScopes.Hold?
    /// The clock that stamps `Workspace.lastOpened`.
    private let now: DateProvider

    // MARK: - Initialization

    /// Initialize the workspace manager with the specified user defaults and an
    /// optional security-scoped bookmark store (sandboxed target only).
    public init(
        userDefaults: UserDefaults = .standard,
        bookmarkStore: (any SecurityScopedBookmarkStoring)? = nil,
        securityScopes: HeldSecurityScopes = .shared,
        now: DateProvider = .system
    ) {
        self.userDefaults = userDefaults
        self.bookmarkStore = bookmarkStore
        self.securityScopes = securityScopes
        self.now = now
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
            holdScope(of: resolved)
            return
        }
        // Freshly granted URL (e.g. from NSOpenPanel): hold the scope and persist
        // a bookmark, keyed by this path, so the folder can be reopened next launch.
        holdScope(of: url)
        bookmarkStore.saveBookmark(for: url)
    }

    /// Start the security scope `scopedURL` carries and hold it until `endAccess()`.
    private func holdScope(of scopedURL: URL) {
        _ = scopedURL.startAccessingSecurityScopedResource()
        activeScope = securityScopes.hold { scopedURL.stopAccessingSecurityScopedResource() }
    }

    /// Release the currently held security scope, if any. It ends once no lint that
    /// started while it was open is still running.
    private func endAccess() {
        if let activeScope {
            securityScopes.release(activeScope)
        }
        activeScope = nil
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

        // Both branches stamp `lastOpened`, because both of them are an open. Only the
        // already-in-recents branch used to, which left the value nil until the second open.
        let openedAt = now()

        // Check if workspace already exists in recent workspaces
        if let existingIndex = recentWorkspaces.firstIndex(where: { $0.path == url }) {
            // Move existing workspace to top
            let existing = recentWorkspaces.remove(at: existingIndex)
            var updated = existing
            updated.lastOpened = openedAt
            recentWorkspaces.insert(updated, at: 0)
            currentWorkspace = updated
            // Persist the reordered list so the "most recent" order survives relaunch;
            // the new-workspace branch persists via addToRecentWorkspaces below.
            saveRecentWorkspaces()
        } else {
            // Create new workspace
            var workspace = Workspace(path: url)
            workspace.lastOpened = openedAt
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
