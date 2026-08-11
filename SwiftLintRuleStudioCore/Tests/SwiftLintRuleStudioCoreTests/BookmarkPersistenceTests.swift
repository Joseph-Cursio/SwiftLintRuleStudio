//
//  BookmarkPersistenceTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Explorer persists security-scoped bookmarks so a recent workspace can be
//  reopened after relaunch. Studio doesn't need them — it isn't sandboxed — so
//  this path is only exercised by the App Store edition.
//
//  These cover the store's logic from the package suite; bookmark resolution
//  under a real sandbox's entitlements is not exercised here.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@Suite("Security-scoped bookmark persistence")
struct BookmarkPersistenceTests {

    /// An isolated defaults suite, so these never touch the real app's state.
    private static func makeIsolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "SwiftLintRuleExplorerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    private static func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkPersistenceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("A saved bookmark resolves back to the same directory")
    func savedBookmarkResolves() throws {
        let (defaults, suiteName) = try Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = UserDefaultsBookmarkStore(userDefaults: defaults)
        store.saveBookmark(for: directory)

        let resolved = store.resolveURL(forPath: directory.path)

        // Resolution goes through the bookmark, so compare the resolved
        // filesystem identity rather than the string — /var vs /private/var.
        #expect(resolved?.resolvingSymlinksInPath() == directory.resolvingSymlinksInPath())
    }

    @Test("An unknown path resolves to nothing")
    func unknownPathResolvesToNil() throws {
        let (defaults, suiteName) = try Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsBookmarkStore(userDefaults: defaults)

        #expect(store.resolveURL(forPath: "/nowhere/\(UUID().uuidString)") == nil)
    }

    @Test("Bookmarks survive a new store over the same defaults")
    func bookmarksSurviveRelaunch() throws {
        let (defaults, suiteName) = try Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        UserDefaultsBookmarkStore(userDefaults: defaults).saveBookmark(for: directory)

        // A fresh store standing in for the next launch: this is the whole point
        // of persisting bookmarks, so a sandboxed user keeps access to a
        // workspace they already granted.
        let afterRelaunch = UserDefaultsBookmarkStore(userDefaults: defaults)

        #expect(afterRelaunch.resolveURL(forPath: directory.path) != nil)
    }

    @Test("Saving two workspaces keeps both resolvable")
    func multipleBookmarksCoexist() throws {
        let (defaults, suiteName) = try Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = try Self.makeTempDirectory()
        let second = try Self.makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let store = UserDefaultsBookmarkStore(userDefaults: defaults)
        store.saveBookmark(for: first)
        store.saveBookmark(for: second)

        #expect(store.resolveURL(forPath: first.path) != nil)
        #expect(store.resolveURL(forPath: second.path) != nil)
    }

    @Test("A store on separate defaults sees nothing")
    func storesAreIsolatedByDefaults() throws {
        let (defaultsA, suiteA) = try Self.makeIsolatedDefaults()
        let (defaultsB, suiteB) = try Self.makeIsolatedDefaults()
        defer {
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }

        let directory = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        UserDefaultsBookmarkStore(userDefaults: defaultsA).saveBookmark(for: directory)

        #expect(UserDefaultsBookmarkStore(userDefaults: defaultsB)
            .resolveURL(forPath: directory.path) == nil)
    }
}
