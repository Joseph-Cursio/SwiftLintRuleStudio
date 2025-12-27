//
//  WorkspaceManagerTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for WorkspaceManager service
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// WorkspaceManager is @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
struct WorkspaceManagerTests {
    
    // Helper to run WorkspaceManager operations on MainActor with isolated UserDefaults
    private func withWorkspaceManager<T: Sendable>(
        testName: String = #function,
        operation: @MainActor (WorkspaceManager) throws -> T
    ) async throws -> T {
        try await MainActor.run {
            let manager = WorkspaceManager.createForTesting(testName: testName)
            return try operation(manager)
        }
    }
    
    private func withWorkspaceManagerAsync<T: Sendable>(
        testName: String = #function,
        operation: @MainActor @escaping (WorkspaceManager) async throws -> T
    ) async throws -> T {
        return try await Task { @MainActor in
            let manager = WorkspaceManager.createForTesting(testName: testName)
            return try await operation(manager)
        }.value
    }
    
    // MARK: - Test Helpers
    
    // Use WorkspaceTestHelpers for creating valid Swift workspaces
    // This ensures WorkspaceManager validation passes
    
    // MARK: - Workspace Opening Tests
    
    @Test("WorkspaceManager opens valid workspace directory")
    func testOpenValidWorkspace() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        let (currentWorkspace, workspacePath, workspaceName) = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace)
            return (manager.currentWorkspace, manager.currentWorkspace?.path, manager.currentWorkspace?.name)
        }
        
        #expect(currentWorkspace != nil)
        #expect(workspacePath == workspace)
        #expect(workspaceName == workspace.lastPathComponent)
    }
    
    @Test("WorkspaceManager rejects non-directory paths")
    func testRejectNonDirectory() async throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).txt")
        
        // Create a file (not a directory)
        try "test".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        await #expect(throws: WorkspaceError.self) {
            try await withWorkspaceManager { manager in
                try manager.openWorkspace(at: tempFile)
            }
        }
    }
    
    @Test("WorkspaceManager rejects non-existent paths")
    func testRejectNonExistentPath() async throws {
        let nonExistentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        
        await #expect(throws: WorkspaceError.self) {
            try await withWorkspaceManager { manager in
                try manager.openWorkspace(at: nonExistentPath)
            }
        }
    }
    
    @Test("WorkspaceManager sets config path correctly")
    func testConfigPathSetCorrectly() async throws {
        let workspace = try WorkspaceTestHelpers.createWorkspaceWithConfig()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        let expectedConfigPath = workspace.appendingPathComponent(".swiftlint.yml")
        let configPath = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace)
            return manager.currentWorkspace?.configPath
        }
        
        #expect(configPath == expectedConfigPath)
    }
    
    // MARK: - Recent Workspaces Tests
    
    @Test("WorkspaceManager adds workspace to recent workspaces")
    func testAddToRecentWorkspaces() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        let (count, firstPath) = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace)
            return (manager.recentWorkspaces.count, manager.recentWorkspaces.first?.path)
        }
        
        #expect(count == 1)
        #expect(firstPath == workspace)
    }
    
    @Test("WorkspaceManager limits recent workspaces count")
    func testLimitRecentWorkspaces() async throws {
        // Create workspaces first
        var tempDirs: [URL] = []
        for i in 0..<15 {
            let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
            tempDirs.append(workspace)
        }
        
        defer {
            for dir in tempDirs {
                WorkspaceTestHelpers.cleanupWorkspace(dir)
            }
        }
        
        // Open all workspaces
        let count = try await withWorkspaceManager { manager in
            for workspace in tempDirs {
                try manager.openWorkspace(at: workspace)
            }
            return manager.recentWorkspaces.count
        }
        
        // Should be limited to maxRecentWorkspaces (10)
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
        
        // Open first workspace
        let firstPath1 = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace1)
            return manager.recentWorkspaces.first?.path
        }
        #expect(firstPath1 == workspace1)
        
        // Open second workspace
        let firstPath2 = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace1)
            try manager.openWorkspace(at: workspace2)
            return manager.recentWorkspaces.first?.path
        }
        #expect(firstPath2 == workspace2)
        
        // Re-open first workspace - should move to top
        let (firstPath3, count) = try await withWorkspaceManager { manager in
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
        
        let (count, firstPath) = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace1)
            try manager.openWorkspace(at: workspace2)
            
            #expect(manager.recentWorkspaces.count == 2)
            
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
        
        let isEmpty = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace1)
            try manager.openWorkspace(at: workspace2)
            
            #expect(manager.recentWorkspaces.count == 2)
            
            manager.clearRecentWorkspaces()
            
            return manager.recentWorkspaces.isEmpty
        }
        
        #expect(isEmpty)
    }
    
    // MARK: - Workspace Closing Tests
    
    @Test("WorkspaceManager closes current workspace")
    func testCloseWorkspace() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        let (hasWorkspace, isNil) = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace)
            let hasWorkspace = manager.currentWorkspace != nil
            manager.closeWorkspace()
            return (hasWorkspace, manager.currentWorkspace == nil)
        }
        
        #expect(hasWorkspace)
        #expect(isNil)
    }
    
    // MARK: - Persistence Tests
    
    @Test("WorkspaceManager persists recent workspaces")
    func testPersistRecentWorkspaces() async throws {
        let tempDir1 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        let tempDir2 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer {
            WorkspaceTestHelpers.cleanupWorkspace(tempDir1)
            WorkspaceTestHelpers.cleanupWorkspace(tempDir2)
        }
        
        // Create first manager and add workspaces
        let count1 = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir1)
            try manager.openWorkspace(at: tempDir2)
            return manager.recentWorkspaces.count
        }
        #expect(count1 == 2)
        
        // Create new manager - should load from persistence
        let (count2, hasDir1, hasDir2) = try await withWorkspaceManager { manager in
            let count = manager.recentWorkspaces.count
            let hasDir1 = manager.recentWorkspaces.contains { $0.path == tempDir1 }
            let hasDir2 = manager.recentWorkspaces.contains { $0.path == tempDir2 }
            return (count, hasDir1, hasDir2)
        }
        
        #expect(count2 == 2)
        #expect(hasDir1)
        #expect(hasDir2)
    }
    
    @Test("WorkspaceManager filters out non-existent workspaces on load")
    func testFilterNonExistentWorkspaces() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        
        // Create manager and add workspace
        let count1 = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return manager.recentWorkspaces.count
        }
        #expect(count1 == 1)
        
        // Delete the directory
        WorkspaceTestHelpers.cleanupWorkspace(tempDir)
        
        // Create new manager - should filter out non-existent workspace
        let isEmpty = try await withWorkspaceManager { manager in
            return manager.recentWorkspaces.isEmpty
        }
        
        #expect(isEmpty)
    }
    
    @Test("WorkspaceManager updates last analyzed time")
    func testUpdateLastAnalyzedTime() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        // Use helper to access WorkspaceManager on MainActor
        let (initialTime, updatedTime) = try await withWorkspaceManagerAsync { manager in
            try manager.openWorkspace(at: tempDir)
            let initial = manager.recentWorkspaces.first?.lastAnalyzed
            
            // Wait a moment
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Re-open workspace
            try manager.openWorkspace(at: tempDir)
            let updated = manager.recentWorkspaces.first?.lastAnalyzed
            
            return (initial, updated)
        }
        
        if let initial = initialTime, let updated = updatedTime {
            #expect(updated > initial)
        } else {
            // At least one should be set
            #expect(updatedTime != nil || initialTime != nil)
        }
    }
    
    // MARK: - Edge Cases
    
    @Test("WorkspaceManager handles multiple rapid opens")
    func testMultipleRapidOpens() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        let (count, currentPath) = try await withWorkspaceManager { manager in
            // Rapidly open the same workspace multiple times
            for _ in 0..<10 {
                try manager.openWorkspace(at: tempDir)
            }
            return (manager.recentWorkspaces.count, manager.currentWorkspace?.path)
        }
        
        // Should only have one entry in recent workspaces
        #expect(count == 1)
        #expect(currentPath == tempDir)
    }
    
    @Test("WorkspaceManager handles workspace with special characters in path")
    func testWorkspaceWithSpecialCharacters() async throws {
        // Create directory with special characters
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        
        let tempDir = tempBase.appendingPathComponent("Test Workspace (v1.0)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Add a Swift file to make it a valid Swift workspace
        let swiftFile = tempDir.appendingPathComponent("TestFile.swift")
        try "// Test file".write(to: swiftFile, atomically: true, encoding: .utf8)
        
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempBase) }
        
        let (currentWorkspace, path, name) = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return (manager.currentWorkspace != nil, manager.currentWorkspace?.path, manager.currentWorkspace?.name)
        }
        
        #expect(currentWorkspace)
        #expect(path == tempDir)
        #expect(name == "Test Workspace (v1.0)")
    }
    
    // MARK: - Config File Detection Tests
    
    @Test("WorkspaceManager detects missing config file")
    func testDetectMissingConfigFile() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        let isMissing = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return manager.configFileMissing
        }
        
        // Config file should not exist
        #expect(isMissing == true)
    }
    
    @Test("WorkspaceManager detects existing config file")
    func testDetectExistingConfigFile() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        // Create a config file
        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        try "# Test config".write(to: configPath, atomically: true, encoding: .utf8)
        
        let isMissing = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            return manager.configFileMissing
        }
        
        // Config file should exist
        #expect(isMissing == false)
    }
    
    @Test("WorkspaceManager creates default config file")
    func testCreateDefaultConfigFile() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        
        // Verify config file doesn't exist
        #expect(FileManager.default.fileExists(atPath: configPath.path) == false)
        
        let (createdPath, isMissingAfter, fileExists) = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            #expect(manager.configFileMissing == true)
            
            // Create default config file
            let createdPath = try manager.createDefaultConfigFile()
            return (createdPath, manager.configFileMissing, FileManager.default.fileExists(atPath: configPath.path))
        }
        
        // Verify config file was created
        #expect(createdPath != nil)
        #expect(createdPath == configPath)
        #expect(fileExists == true)
        #expect(isMissingAfter == false)
        
        // Verify config file content
        let content = try String(contentsOf: configPath, encoding: .utf8)
        #expect(content.contains("excluded:"))
        #expect(content.contains(".build"))
        #expect(content.contains("Pods"))
        #expect(content.contains("line_length:"))
    }
    
    @Test("WorkspaceManager does not overwrite existing config file")
    func testDoesNotOverwriteExistingConfigFile() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        // Create an existing config file with custom content
        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        let customContent = "# Custom config\ncustom_rule: true"
        try customContent.write(to: configPath, atomically: true, encoding: .utf8)
        
        let createdPath = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            
            // Create default config file (should return existing path without overwriting)
            return try manager.createDefaultConfigFile()
        }
        
        // Verify it returned the existing path
        #expect(createdPath == configPath)
        
        // Verify original content is preserved
        let content = try String(contentsOf: configPath, encoding: .utf8)
        #expect(content == customContent)
    }
    
    @Test("WorkspaceManager updates configFileMissing when workspace closes")
    func testConfigFileMissingResetsOnClose() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        let (isMissingBefore, isMissingAfter) = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir)
            
            // Config file should be missing
            let isMissingBefore = manager.configFileMissing
            #expect(isMissingBefore == true)
            
            // Close workspace
            manager.closeWorkspace()
            
            // Config file missing should be reset
            return (isMissingBefore, manager.configFileMissing)
        }
        
        #expect(isMissingBefore == true)
        #expect(isMissingAfter == false)
    }
    
    @Test("WorkspaceManager checks config file on workspace change")
    func testCheckConfigFileOnWorkspaceChange() async throws {
        let tempDir1 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        let tempDir2 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer {
            WorkspaceTestHelpers.cleanupWorkspace(tempDir1)
            WorkspaceTestHelpers.cleanupWorkspace(tempDir2)
        }
        
        // Create config file in first workspace
        let configPath1 = tempDir1.appendingPathComponent(".swiftlint.yml")
        try "# Config 1".write(to: configPath1, atomically: true, encoding: .utf8)
        
        // Open first workspace (has config)
        let missing1 = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir1)
            return manager.configFileMissing
        }
        #expect(missing1 == false)
        
        // Open second workspace (no config)
        let missing2 = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir1)
            try manager.openWorkspace(at: tempDir2)
            return manager.configFileMissing
        }
        #expect(missing2 == true)
        
        // Switch back to first workspace
        let missing3 = try await withWorkspaceManager { manager in
            try manager.openWorkspace(at: tempDir1)
            try manager.openWorkspace(at: tempDir2)
            try manager.openWorkspace(at: tempDir1)
            return manager.configFileMissing
        }
        #expect(missing3 == false)
    }
}

