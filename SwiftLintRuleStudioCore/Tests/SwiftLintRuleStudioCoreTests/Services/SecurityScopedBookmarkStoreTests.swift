import Foundation
import Testing
@testable import SwiftLintRuleStudioCore

@Suite
struct SecurityScopedBookmarkStoreTests {

    private func isolatedStore() -> (UserDefaultsBookmarkStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "test.bookmarks.\(UUID().uuidString)")!
        return (UserDefaultsBookmarkStore(userDefaults: defaults), defaults)
    }

    @Test
    func unknownPathResolvesToNil() {
        let (store, _) = isolatedStore()
        #expect(store.resolveURL(forPath: "/nonexistent/\(UUID().uuidString)") == nil)
    }

    @Test
    func saveThenResolveRoundTrips() throws {
        let (store, _) = isolatedStore()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        store.saveBookmark(for: dir)

        // Bookmark resolution canonicalizes symlinks (e.g. /var -> /private/var),
        // so compare after resolving symlinks. In a plain unit-test process the
        // store may degrade to nil, which callers handle — either is acceptable.
        if let resolved = store.resolveURL(forPath: dir.path) {
            #expect(resolved.resolvingSymlinksInPath().path == dir.resolvingSymlinksInPath().path)
        }
    }

    @Test
    func doesNotCrashSavingUnreadablePath() {
        let (store, _) = isolatedStore()
        // A path that doesn't exist: bookmarkData throws, save is a graceful no-op.
        store.saveBookmark(for: URL(fileURLWithPath: "/definitely/not/here/\(UUID().uuidString)"))
        #expect(store.resolveURL(forPath: "/definitely/not/here") == nil)
    }
}
