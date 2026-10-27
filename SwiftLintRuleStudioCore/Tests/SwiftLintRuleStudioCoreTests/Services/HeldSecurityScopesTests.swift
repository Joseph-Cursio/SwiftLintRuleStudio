//
//  HeldSecurityScopesTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  In the sandboxed Explorer, a workspace closed or replaced while an in-process lint is
//  still reading it must keep its security scope until that lint is done: SwiftLint ends the
//  process, the app, on a nested config it has found but can't read.
//
//  These cover when a scope ends, with stand-in scopes. Whether the sandbox denies reads
//  once a real security-scoped URL stops being accessed is not exercised here.
//

import Foundation
import os
@testable import SwiftLintCLISeam
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@Suite("Held security scopes")
struct HeldSecurityScopesTests {

    /// A stand-in scope: counts how many times it was ended.
    private static func hold(in scopes: HeldSecurityScopes) -> (HeldSecurityScopes.Hold, OSAllocatedUnfairLock<Int>) {
        let stops = OSAllocatedUnfairLock(initialState: 0)
        let hold = scopes.hold { stops.withLock { $0 += 1 } }
        return (hold, stops)
    }

    @Test("A scope released with no lint running ends at once")
    func releasedScopeEndsAtOnce() {
        let scopes = HeldSecurityScopes()
        let (hold, stops) = Self.hold(in: scopes)

        scopes.release(hold)

        #expect(stops.withLock { $0 } == 1)
        #expect(scopes.openCount == 0)
    }

    @Test("A scope released mid-lint ends when the lint is done")
    func scopeReleasedMidLintEndsAfterIt() {
        let scopes = HeldSecurityScopes()
        let (hold, stops) = Self.hold(in: scopes)

        scopes.keepingOpen {
            scopes.release(hold)
            #expect(stops.withLock { $0 } == 0)
        }

        #expect(stops.withLock { $0 } == 1)
        #expect(scopes.openCount == 0)
    }

    /// A lint queued before the workspace closed can start after the release, while an earlier
    /// lint still keeps the scope open. It reads through the scope like any other, so it keeps
    /// it open too, rather than losing it partway when the earlier lint ends.
    @Test("A lint that starts while a released scope is still open keeps it open")
    func laterLintKeepsReleasedScopeOpen() {
        let scopes = HeldSecurityScopes()
        let (hold, stops) = Self.hold(in: scopes)
        let earlierStarted = DispatchSemaphore(value: 0)
        let earlierMayEnd = DispatchSemaphore(value: 0)
        let earlierEnded = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            scopes.keepingOpen {
                earlierStarted.signal()
                earlierMayEnd.wait()
            }
            earlierEnded.signal()
        }
        earlierStarted.wait()
        scopes.release(hold)

        scopes.keepingOpen {
            earlierMayEnd.signal()
            earlierEnded.wait()
            #expect(stops.withLock { $0 } == 0)
        }

        #expect(stops.withLock { $0 } == 1)
    }

    @Test("A lint keeps open only the scopes held when it started")
    func lintKeepsOnlyEarlierScopes() {
        let scopes = HeldSecurityScopes()

        scopes.keepingOpen {
            let (hold, stops) = Self.hold(in: scopes)
            scopes.release(hold)
            #expect(stops.withLock { $0 } == 1)
        }
    }

    @Test("A scope released twice ends once")
    func releasingTwiceEndsOnce() {
        let scopes = HeldSecurityScopes()
        let (hold, stops) = Self.hold(in: scopes)

        scopes.keepingOpen {
            scopes.release(hold)
            scopes.release(hold)
        }
        scopes.release(hold)

        #expect(stops.withLock { $0 } == 1)
    }

    // MARK: - WorkspaceManager

    /// A sandboxed manager with no stored bookmarks: it holds the folder's own URL's scope.
    private struct NoBookmarks: SecurityScopedBookmarkStoring {
        func saveBookmark(for _: URL) {}
        func resolveURL(forPath _: String) -> URL? { nil }
    }

    @MainActor
    private static func makeManager(_ testName: String, scopes: HeldSecurityScopes) -> WorkspaceManager {
        WorkspaceManager(
            userDefaults: IsolatedUserDefaults.create(for: testName),
            bookmarkStore: NoBookmarks(),
            securityScopes: scopes
        )
    }

    @Test("A workspace closed mid-lint keeps its scope until the lint is done")
    @MainActor
    func closedWorkspaceKeepsScopeForLint() throws {
        let path = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(path) }
        let scopes = HeldSecurityScopes()
        let manager = Self.makeManager(#function, scopes: scopes)
        try manager.openWorkspace(at: path)
        #expect(scopes.openCount == 1)

        scopes.keepingOpen {
            manager.closeWorkspace()
            #expect(scopes.openCount == 1)
        }

        #expect(scopes.openCount == 0)
    }

    @Test("A workspace replaced mid-lint keeps its scope until the lint is done")
    @MainActor
    func replacedWorkspaceKeepsScopeForLint() throws {
        let first = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        let second = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer {
            WorkspaceTestHelpers.cleanupWorkspace(first)
            WorkspaceTestHelpers.cleanupWorkspace(second)
        }
        let scopes = HeldSecurityScopes()
        let manager = Self.makeManager(#function, scopes: scopes)
        try manager.openWorkspace(at: first)

        try scopes.keepingOpen {
            try manager.openWorkspace(at: second)
            #expect(scopes.openCount == 2)
        }

        #expect(scopes.openCount == 1)
        manager.closeWorkspace()
        #expect(scopes.openCount == 0)
    }
}
