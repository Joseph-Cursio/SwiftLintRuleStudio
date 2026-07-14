//
//  SecurityScopedBookmarkStore.swift
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

/// `UserDefaults`-backed bookmark store, keyed by the folder's path.
///
/// `@unchecked Sendable`: the only stored property is a `UserDefaults`, which is
/// documented thread-safe; it isn't formally `Sendable`.
public nonisolated struct UserDefaultsBookmarkStore: SecurityScopedBookmarkStoring, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let storageKey = "SwiftLintRuleStudio.securityScopedBookmarks"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func saveBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }
        var all = storedBookmarks()
        all[url.path] = data
        userDefaults.set(all, forKey: storageKey)
    }

    public func resolveURL(forPath path: String) -> URL? {
        guard let data = storedBookmarks()[path] else {
            return nil
        }
        var isStale = false
        let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        // If the bookmark is stale, the URL still resolves for this launch; a
        // fresh bookmark is written the next time the user re-grants access.
        return url
    }

    private func storedBookmarks() -> [String: Data] {
        userDefaults.dictionary(forKey: storageKey) as? [String: Data] ?? [:]
    }
}
