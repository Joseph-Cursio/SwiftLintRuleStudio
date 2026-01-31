//
//  WorkspaceManagerPersistenceTests.swift
//  SwiftLIntRuleStudioTests
//
//  Persistence and edge case tests for WorkspaceManager
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct WorkspaceManagerPersistenceTests {
    @Test("WorkspaceManager closes current workspace")
    func testCloseWorkspace() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let (hasWorkspace, isNil) = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace)
            let hasWorkspace = manager.currentWorkspace != nil
            manager.closeWorkspace()
            return (hasWorkspace, manager.currentWorkspace == nil)
        }

        #expect(hasWorkspace)
        #expect(isNil)
    }

    @Test("WorkspaceManager persists recent workspaces")
    func testPersistRecentWorkspaces() async throws {
        let tempDir1 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        let tempDir2 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer {
            WorkspaceTestHelpers.cleanupWorkspace(tempDir1)
            WorkspaceTestHelpers.cleanupWorkspace(tempDir2)
        }

        let (count1, count2, hasDir1, hasDir2) = try await MainActor.run {
            let sharedDefaults = IsolatedUserDefaults.createShared(for: #function)

            let manager1 = WorkspaceManager(userDefaults: sharedDefaults)
            try manager1.openWorkspace(at: tempDir1)
            try manager1.openWorkspace(at: tempDir2)
            let count1 = manager1.recentWorkspaces.count

            let manager2 = WorkspaceManager(userDefaults: sharedDefaults)
            let count2 = manager2.recentWorkspaces.count
            let hasDir1 = manager2.recentWorkspaces.contains { $0.path == tempDir1 }
            let hasDir2 = manager2.recentWorkspaces.contains { $0.path == tempDir2 }
            return (count1, count2, hasDir1, hasDir2)
        }
        #expect(count1 == 2)
        #expect(count2 == 2)
        #expect(hasDir1)
        #expect(hasDir2)
    }

    @Test("WorkspaceManager filters out non-existent workspaces on load")
    func testFilterNonExistentWorkspaces() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()

        let count1 = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return manager.recentWorkspaces.count
        }
        #expect(count1 == 1)

        WorkspaceTestHelpers.cleanupWorkspace(tempDir)

        let isEmpty = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            manager.recentWorkspaces.isEmpty
        }

        #expect(isEmpty)
    }

    @Test("WorkspaceManager handles multiple rapid opens")
    func testMultipleRapidOpens() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let (count, currentPath) = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            for _ in 0..<10 {
                try manager.openWorkspace(at: tempDir)
            }
            return (manager.recentWorkspaces.count, manager.currentWorkspace?.path)
        }

        #expect(count == 1)
        #expect(currentPath == tempDir)
    }

    @Test("WorkspaceManager handles workspace with special characters in path")
    func testWorkspaceWithSpecialCharacters() async throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)

        let tempDir = tempBase.appendingPathComponent("Test Workspace (v1.0)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let swiftFile = tempDir.appendingPathComponent("TestFile.swift")
        try "// Test file".write(to: swiftFile, atomically: true, encoding: .utf8)

        defer { WorkspaceTestHelpers.cleanupWorkspace(tempBase) }

        let (currentWorkspace, path, name) = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return (manager.currentWorkspace != nil, manager.currentWorkspace?.path, manager.currentWorkspace?.name)
        }

        #expect(currentWorkspace)
        #expect(path == tempDir)
        #expect(name == "Test Workspace (v1.0)")
    }
}
