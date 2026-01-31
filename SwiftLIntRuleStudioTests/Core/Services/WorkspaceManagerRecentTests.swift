//
//  WorkspaceManagerRecentTests.swift
//  SwiftLIntRuleStudioTests
//
//  Recent workspace tests
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

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
