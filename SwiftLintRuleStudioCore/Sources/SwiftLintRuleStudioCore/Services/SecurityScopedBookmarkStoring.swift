//
//  SecurityScopedBookmarkStoring.swift
//  SwiftLintRuleStudio
//
//  Lets a sandboxed app regain access to a user-selected folder across launches.
//  Under the App Sandbox, a folder the user picks (via NSOpenPanel) is accessible
//  only for that session; to reopen it later — e.g. from the Recent Workspaces
//  list — the app must persist a *security-scoped bookmark* and resolve it.
//
//  The non-sandboxed Studio target does not inject a store (WorkspaceManager falls
//  back to plain paths, unchanged). The sandboxed Explorer target injects
//  `UserDefaultsBookmarkStore`.
//

import Foundation

public protocol SecurityScopedBookmarkStoring: Sendable {
    /// Create and persist a security-scoped bookmark for a folder the user has
    /// granted access to (e.g. the result of an `NSOpenPanel`).
    func saveBookmark(for url: URL)

    /// Resolve a previously stored bookmark back into a security-scoped URL, or
    /// `nil` if none is stored or it cannot be resolved. The caller must invoke
    /// `startAccessingSecurityScopedResource()` on the result before reading.
    func resolveURL(forPath path: String) -> URL?
}
