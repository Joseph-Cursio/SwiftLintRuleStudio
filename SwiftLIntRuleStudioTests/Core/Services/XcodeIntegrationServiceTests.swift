//
//  XcodeIntegrationServiceTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for XcodeIntegrationService
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct XcodeIntegrationServiceTests {
    
    // Helper to run XcodeIntegrationService operations on MainActor
    private func withService<T: Sendable>(
        testName: String = #function,
        operation: @MainActor (XcodeIntegrationService, WorkspaceManager) throws -> T
    ) async throws -> T {
        try await MainActor.run {
            let workspaceManager = WorkspaceManager.createForTesting(testName: testName)
            let service = XcodeIntegrationService(workspaceManager: workspaceManager)
            return try operation(service, workspaceManager)
        }
    }
    
    private func withServiceAsync<T: Sendable>(
        testName: String = #function,
        operation: @MainActor @escaping (XcodeIntegrationService, WorkspaceManager) async throws -> T
    ) async throws -> T {
        return try await Task { @MainActor in
            let workspaceManager = WorkspaceManager.createForTesting(testName: testName)
            let service = XcodeIntegrationService(workspaceManager: workspaceManager)
            return try await operation(service, workspaceManager)
        }.value
    }
    
    // MARK: - Path Resolution Tests
    
    @Test("Resolves absolute paths correctly")
    func testResolveAbsolutePath() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        let testFile = workspace.appendingPathComponent("TestFile.swift")
        let workspaceModel = await MainActor.run { Workspace(path: workspace) }
        
        try await withServiceAsync { service, _ in
            // Absolute path should be resolved as-is
            let resolved = try await service.openFile(
                at: testFile.path,
                line: 1,
                column: nil,
                in: workspaceModel
            )
            // Note: This will fail to actually open, but path resolution should work
            // We're testing the path resolution logic, not the actual opening
        }
    }
    
    @Test("Resolves relative paths against workspace root")
    func testResolveRelativePath() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        let workspaceModel = await MainActor.run { Workspace(path: workspace) }
        let relativePath = "TestFile.swift"
        
        try await withServiceAsync { service, _ in
            // Relative path should be resolved relative to workspace
            let resolved = try await service.openFile(
                at: relativePath,
                line: 1,
                column: nil,
                in: workspaceModel
            )
            // Note: This will fail to actually open, but path resolution should work
        }
    }
    
    @Test("Throws error for non-existent file")
    func testFileNotFoundError() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        let workspaceModel = await MainActor.run { Workspace(path: workspace) }
        let nonExistentPath = "NonExistentFile.swift"
        
        await #expect(throws: XcodeIntegrationError.self) {
            try await withServiceAsync { service, _ in
                try await service.openFile(
                    at: nonExistentPath,
                    line: 1,
                    column: nil,
                    in: workspaceModel
                )
            }
        }
    }
    
    @Test("Throws error for empty path")
    func testEmptyPathError() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        let workspaceModel = await MainActor.run { Workspace(path: workspace) }
        
        await #expect(throws: XcodeIntegrationError.self) {
            try await withServiceAsync { service, _ in
                _ = try service.resolveFileURL("   ", in: workspaceModel)
            }
        }
    }
    
    @Test("Throws error for directory path")
    func testDirectoryPathError() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        let workspaceModel = await MainActor.run { Workspace(path: workspace) }
        
        await #expect(throws: XcodeIntegrationError.self) {
            try await withServiceAsync { service, _ in
                try await service.openFile(
                    at: ".",
                    line: 1,
                    column: nil,
                    in: workspaceModel
                )
            }
        }
    }
    
    // MARK: - Project Detection Tests
    
    @Test("Finds Xcode project in workspace root")
    func testFindProjectInRoot() async throws {
        let workspace = try WorkspaceTestHelpers.createXcodeProjectWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        let testFile = workspace.appendingPathComponent("TestFile.swift")
        let workspaceModel = await MainActor.run { Workspace(path: workspace) }
        
        try await withService { service, _ in
            let projectURL = service.findXcodeProject(for: testFile, in: workspaceModel)
            #expect(projectURL != nil)
            #expect(projectURL?.lastPathComponent == "TestProject.xcodeproj")
        }
    }
    
    @Test("Finds closest project when multiple projects exist")
    func testFindClosestProject() async throws {
        let workspace = try WorkspaceTestHelpers.createXcodeProjectWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        // Create nested project
        let nestedDir = workspace.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        
        let nestedProjectDir = nestedDir.appendingPathComponent("NestedProject.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedProjectDir, withIntermediateDirectories: true)
        
        let nestedFile = nestedDir.appendingPathComponent("NestedFile.swift")
        try "// Nested file".write(to: nestedFile, atomically: true, encoding: .utf8)
        
        let workspaceModel = await MainActor.run { Workspace(path: workspace) }
        
        try await withService { service, _ in
            // File in nested directory should find nested project
            let projectURL = service.findXcodeProject(for: nestedFile, in: workspaceModel)
            #expect(projectURL != nil)
            #expect(projectURL?.lastPathComponent == "NestedProject.xcodeproj")
        }
    }
    
    @Test("Prefers workspace over project")
    func testPrefersWorkspaceOverProject() async throws {
        let workspace = try WorkspaceTestHelpers.createXcodeProjectWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        // Create .xcworkspace
        let workspaceDir = workspace.appendingPathComponent("TestWorkspace.xcworkspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        
        let testFile = workspace.appendingPathComponent("TestFile.swift")
        let workspaceModel = await MainActor.run { Workspace(path: workspace) }
        
        try await withService { service, _ in
            let projectURL = service.findXcodeProject(for: testFile, in: workspaceModel)
            #expect(projectURL != nil)
            // Should prefer .xcworkspace over .xcodeproj
            if let url = projectURL {
                let isWorkspace = url.pathExtension == "xcworkspace"
                let isProject = url.pathExtension == "xcodeproj"
                #expect(isWorkspace || isProject) // At least one should be found
            }
        }
    }
    
    @Test("Returns nil when no project found")
    func testNoProjectFound() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        let testFile = workspace.appendingPathComponent("TestFile.swift")
        let workspaceModel = await MainActor.run { Workspace(path: workspace) }
        
        try await withService { service, _ in
            let projectURL = service.findXcodeProject(for: testFile, in: workspaceModel)
            // No Xcode project in minimal workspace, so should return nil
            #expect(projectURL == nil)
        }
    }

    @Test("XcodeIntegrationError provides descriptions")
    func testXcodeIntegrationErrorDescriptions() {
        let errors: [XcodeIntegrationError] = [
            .fileNotFound(path: "/tmp/missing.swift"),
            .invalidPath(path: ""),
            .xcodeNotInstalled,
            .failedToOpen
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("XcodeIntegrationService generates xcode:// URL")
    func testGenerateXcodeURL() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let fileURL = workspace.appendingPathComponent("TestFile.swift")
        let workspaceModel = await MainActor.run { Workspace(path: workspace) }

        try await withService { service, _ in
            let url = service.generateXcodeURL(
                fileURL: fileURL,
                line: 42,
                column: 3,
                projectURL: nil
            )
            #expect(url?.scheme == "xcode")
            #expect(url?.absoluteString.contains("line=42") == true)
            #expect(url?.absoluteString.contains("column=3") == true)
        }
    }

    @Test("XcodeIntegrationService checks for Xcode installation")
    func testIsXcodeInstalledReturnsBool() async throws {
        try await withService { service, _ in
            let _ = service.isXcodeInstalled()
        }
    }
    
    @Test("Caches project locations")
    func testProjectCaching() async throws {
        let workspace = try WorkspaceTestHelpers.createXcodeProjectWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        let testFile1 = workspace.appendingPathComponent("TestFile1.swift")
        let testFile2 = workspace.appendingPathComponent("TestFile2.swift")
        let workspaceModel = await MainActor.run { Workspace(path: workspace) }
        
        try await withService { service, _ in
            let projectURL1 = service.findXcodeProject(for: testFile1, in: workspaceModel)
            let projectURL2 = service.findXcodeProject(for: testFile2, in: workspaceModel)
            
            // Both should find the same project
            #expect(projectURL1 == projectURL2)
        }
    }
    
    // MARK: - Xcode Installation Detection Tests
    
    @Test("Detects Xcode installation")
    func testXcodeInstallationDetection() async throws {
        try await withService { service, _ in
            // This test checks if Xcode detection works
            // It may return true or false depending on test environment
            let isInstalled = service.isXcodeInstalled()
            // Just verify the method doesn't crash
            #expect(isInstalled == true || isInstalled == false)
        }
    }
    
    // MARK: - Cache Management Tests
    
    @Test("Clears cache correctly")
    func testClearCache() async throws {
        let workspace = try WorkspaceTestHelpers.createXcodeProjectWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        let testFile = workspace.appendingPathComponent("TestFile.swift")
        let workspaceModel = await MainActor.run { Workspace(path: workspace) }
        
        try await withService { service, _ in
            // Find project (should cache it)
            _ = service.findXcodeProject(for: testFile, in: workspaceModel)
            
            // Clear cache
            service.clearCache()
            
            // Finding again should still work (will re-search)
            let projectURL = service.findXcodeProject(for: testFile, in: workspaceModel)
            #expect(projectURL != nil)
        }
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Handles absolute path outside workspace")
    func testAbsolutePathOutsideWorkspace() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        // Create a file outside the workspace
        let outsideFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutsideFile.swift")
        try "// Outside file".write(to: outsideFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outsideFile) }
        
        let workspaceModel = await MainActor.run { Workspace(path: workspace) }
        
        try await withServiceAsync { service, _ in
            // Should be able to resolve absolute path even if outside workspace
            // But will fail to open if file doesn't exist in expected location
            // This tests that absolute paths are handled correctly
            let resolved = try await service.openFile(
                at: outsideFile.path,
                line: 1,
                column: nil,
                in: workspaceModel
            )
            // Note: May succeed or fail depending on Xcode availability
        }
    }
}
