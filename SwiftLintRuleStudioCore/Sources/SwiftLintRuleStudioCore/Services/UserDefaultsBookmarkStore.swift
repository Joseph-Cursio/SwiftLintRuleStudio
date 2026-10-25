//
//  UserDefaultsBookmarkStore.swift
//  SwiftLintRuleStudio
//
//  The bookmark store the sandboxed Explorer target injects. See
//  SecurityScopedBookmarkStoring.swift for why the app keeps bookmarks at all.
//

import Foundation

/// `UserDefaults`-backed bookmark store, keyed by the folder's path.
///
/// `@unchecked Sendable`: the only stored property is a `UserDefaults`, which is
/// documented thread-safe; it isn't formally `Sendable`.
nonisolated public struct UserDefaultsBookmarkStore: SecurityScopedBookmarkStoring, @unchecked Sendable {
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
        // If the bookmark is stale, the URL still resolves for this launch; a
        // fresh bookmark is written the next time the user re-grants access.
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private func storedBookmarks() -> [String: Data] {
        userDefaults.dictionary(forKey: storageKey) as? [String: Data] ?? [:]
    }
}
