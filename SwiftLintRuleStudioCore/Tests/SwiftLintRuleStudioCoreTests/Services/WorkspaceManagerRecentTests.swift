//
//  WorkspaceManagerRecentTests.swift
//  SwiftLintRuleStudioTests
//
//  Recent workspace tests
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct WorkspaceManagerRecentTests {
    @Test("WorkspaceManager adds workspace to recent workspaces")
    func testAddToRecentWorkspaces() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let (count, firstPath) = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace)
            return (manager.recentWorkspaces.count, manager.recentWorkspaces.first?.path)
        }

        #expect(count == 1)
        #expect(firstPath == workspace)
    }

    @Test("WorkspaceManager limits recent workspaces count")
    func testLimitRecentWorkspaces() async throws {
        var tempDirs: [URL] = []
        for _ in 0..<15 {
            let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
            tempDirs.append(workspace)
        }

        defer {
            for dir in tempDirs {
                WorkspaceTestHelpers.cleanupWorkspace(dir)
            }
        }

        let count = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            for workspace in tempDirs {
                try manager.openWorkspace(at: workspace)
            }
            return manager.recentWorkspaces.count
        }

        #expect(count <= 10)
    }

    // Regression for P1.2: the in-memory reorder above is not enough — reopening a
    // workspace already in the recents list must also PERSIST the new order, or the
    // stale order loads back on the next launch. A second manager reading the same
    // UserDefaults stands in for that relaunch.
    @Test("Reopening an already-recent workspace persists the reordered list")
    func testReopenPersistsRecentOrder() async throws {
        let workspaceA = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        let workspaceB = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        let workspaceC = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer {
            WorkspaceTestHelpers.cleanupWorkspace(workspaceA)
            WorkspaceTestHelpers.cleanupWorkspace(workspaceB)
            WorkspaceTestHelpers.cleanupWorkspace(workspaceC)
        }

        let defaults = IsolatedUserDefaults.create(for: #function)

        let reloadedFirst = try await MainActor.run { () -> URL? in
            let manager = WorkspaceManager(userDefaults: defaults)
            try manager.openWorkspace(at: workspaceA)
            try manager.openWorkspace(at: workspaceB)
            try manager.openWorkspace(at: workspaceC)  // persisted order: [C, B, A]
            try manager.openWorkspace(at: workspaceA)  // reopen existing -> [A, C, B]

            // A fresh manager loads from the same store, as on the next app launch.
            let relaunched = WorkspaceManager(userDefaults: defaults)
            return relaunched.recentWorkspaces.first?.path
        }

        #expect(
            reloadedFirst == workspaceA,
            "reopening a recent workspace must persist it to the top for the next launch"
        )
    }

    @Test("WorkspaceManager moves existing workspace to top of recent list")
    func testMoveExistingToTop() async throws {
        let workspace1 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        let workspace2 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer {
            WorkspaceTestHelpers.cleanupWorkspace(workspace1)
            WorkspaceTestHelpers.cleanupWorkspace(workspace2)
        }

        let firstPath1 = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace1)
            return manager.recentWorkspaces.first?.path
        }
        #expect(firstPath1 == workspace1)

        let firstPath2 = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace1)
            try manager.openWorkspace(at: workspace2)
            return manager.recentWorkspaces.first?.path
        }
        #expect(firstPath2 == workspace2)

        let (firstPath3, count) = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace1)
            try manager.openWorkspace(at: workspace2)
            try manager.openWorkspace(at: workspace1)
            return (manager.recentWorkspaces.first?.path, manager.recentWorkspaces.count)
        }
        #expect(firstPath3 == workspace1)
        #expect(count == 2)
    }

    @Test("WorkspaceManager removes workspace from recent workspaces")
    func testRemoveFromRecentWorkspaces() async throws {
        let workspace1 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        let workspace2 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer {
            WorkspaceTestHelpers.cleanupWorkspace(workspace1)
            WorkspaceTestHelpers.cleanupWorkspace(workspace2)
        }

        let (count, firstPath) = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace1)
            try manager.openWorkspace(at: workspace2)

            if let workspace = manager.recentWorkspaces.first(where: { $0.path == workspace1 }) {
                manager.removeFromRecentWorkspaces(workspace)
            }

            return (manager.recentWorkspaces.count, manager.recentWorkspaces.first?.path)
        }

        #expect(count == 1)
        #expect(firstPath == workspace2)
    }

    @Test("WorkspaceManager clears all recent workspaces")
    func testClearRecentWorkspaces() async throws {
        let workspace1 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        let workspace2 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer {
            WorkspaceTestHelpers.cleanupWorkspace(workspace1)
            WorkspaceTestHelpers.cleanupWorkspace(workspace2)
        }

        let count = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace1)
            try manager.openWorkspace(at: workspace2)
            manager.clearRecentWorkspaces()
            return manager.recentWorkspaces.count
        }

        #expect(count == 0)
    }

    @Test("WorkspaceManager updates last analyzed time")
    func testUpdateLastAnalyzed() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let (first, second) = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace)
            let first = manager.recentWorkspaces.first?.lastAnalyzed
            try manager.openWorkspace(at: workspace)
            let second = manager.recentWorkspaces.first?.lastAnalyzed
            return (first, second)
        }

        #expect(first == nil)
        #expect(second != nil)
    }
}
