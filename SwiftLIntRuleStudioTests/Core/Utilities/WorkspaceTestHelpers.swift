//
//  WorkspaceTestHelpers.swift
//  SwiftLIntRuleStudioTests
//
//  Test helpers for setting up Swift project workspaces for testing
//

import Foundation
@testable import SwiftLIntRuleStudio

// Helper to create valid Swift project workspaces for testing
struct WorkspaceTestHelpers {
    
    /// Creates a temporary directory with a valid Swift project structure
    /// This ensures WorkspaceManager validation passes
    static func createValidSwiftWorkspace(
        includePackageSwift: Bool = false,
        includeXcodeProject: Bool = false,
        swiftFileContent: String? = nil
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent("WorkspaceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Create a Swift file (required for validation)
        let swiftFile = tempDir.appendingPathComponent("TestFile.swift")
        let content = swiftFileContent ?? """
        // Test Swift file
        import Foundation
        
        struct TestStruct {
            let value: String
        }
        """
        try content.write(to: swiftFile, atomically: true, encoding: .utf8)
        
        // Optionally add Package.swift
        if includePackageSwift {
            let packageSwift = tempDir.appendingPathComponent("Package.swift")
            let packageContent = """
            // swift-tools-version: 5.9
            import PackageDescription
            
            let package = Package(
                name: "TestPackage",
                targets: [
                    .target(name: "TestPackage")
                ]
            )
            """
            try packageContent.write(to: packageSwift, atomically: true, encoding: .utf8)
        }
        
        // Optionally add Xcode project structure
        if includeXcodeProject {
            let xcodeprojDir = tempDir.appendingPathComponent("TestProject.xcodeproj", isDirectory: true)
            try FileManager.default.createDirectory(at: xcodeprojDir, withIntermediateDirectories: true)
            
            // Create minimal project.pbxproj
            let pbxproj = xcodeprojDir.appendingPathComponent("project.pbxproj")
            let pbxprojContent = """
            // !$*UTF8*$!
            {
                archiveVersion = 1;
                classes = {
                };
                objectVersion = 56;
                objects = {
                };
                rootObject = "000000000000000000000000";
            }
            """
            try pbxprojContent.write(to: pbxproj, atomically: true, encoding: .utf8)
        }
        
        return tempDir
    }
    
    /// Creates a minimal valid Swift workspace (just has a Swift file)
    static func createMinimalSwiftWorkspace() throws -> URL {
        return try createValidSwiftWorkspace()
    }
    
    /// Creates a Swift Package Manager workspace
    static func createSwiftPMWorkspace() throws -> URL {
        return try createValidSwiftWorkspace(includePackageSwift: true)
    }
    
    /// Creates an Xcode project workspace
    static func createXcodeProjectWorkspace() throws -> URL {
        return try createValidSwiftWorkspace(includeXcodeProject: true)
    }
    
    /// Cleans up a test workspace directory
    static func cleanupWorkspace(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    /// Creates a workspace with a .swiftlint.yml config file
    static func createWorkspaceWithConfig(configContent: String = "") throws -> URL {
        let workspace = try createValidSwiftWorkspace()
        
        let configFile = workspace.appendingPathComponent(".swiftlint.yml")
        let content = configContent.isEmpty ? """
        # SwiftLint configuration
        disabled_rules:
          - todo
        """ : configContent
        
        try content.write(to: configFile, atomically: true, encoding: .utf8)
        
        return workspace
    }
    
    /// Creates a workspace with multiple Swift files in subdirectories
    static func createWorkspaceWithNestedFiles() throws -> URL {
        let workspace = try createValidSwiftWorkspace()
        
        // Create nested directories with Swift files
        let sourcesDir = workspace.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        
        let mainFile = sourcesDir.appendingPathComponent("main.swift")
        try "// Main file".write(to: mainFile, atomically: true, encoding: .utf8)
        
        let utilsDir = sourcesDir.appendingPathComponent("Utils", isDirectory: true)
        try FileManager.default.createDirectory(at: utilsDir, withIntermediateDirectories: true)
        
        let utilsFile = utilsDir.appendingPathComponent("Utils.swift")
        try "// Utils file".write(to: utilsFile, atomically: true, encoding: .utf8)
        
        return workspace
    }
}

