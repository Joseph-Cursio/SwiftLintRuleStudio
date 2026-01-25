//
//  WorkspaceTestHelpersTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for WorkspaceTestHelpers utilities
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct WorkspaceTestHelpersTests {
    @Test("WorkspaceTestHelpers creates SwiftPM workspace")
    func testCreateSwiftPMWorkspace() throws {
        let workspace = try WorkspaceTestHelpers.createSwiftPMWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let packageSwift = workspace.appendingPathComponent("Package.swift")
        #expect(FileManager.default.fileExists(atPath: packageSwift.path) == true)
    }

    @Test("WorkspaceTestHelpers creates Xcode project workspace")
    func testCreateXcodeProjectWorkspace() throws {
        let workspace = try WorkspaceTestHelpers.createXcodeProjectWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let projectDir = workspace.appendingPathComponent("TestProject.xcodeproj")
        #expect(FileManager.default.fileExists(atPath: projectDir.path) == true)
    }

    @Test("WorkspaceTestHelpers creates workspace with nested files")
    func testCreateWorkspaceWithNestedFiles() throws {
        let workspace = try WorkspaceTestHelpers.createWorkspaceWithNestedFiles()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let mainFile = workspace.appendingPathComponent("Sources/main.swift")
        let utilsFile = workspace.appendingPathComponent("Sources/Utils/Utils.swift")
        #expect(FileManager.default.fileExists(atPath: mainFile.path) == true)
        #expect(FileManager.default.fileExists(atPath: utilsFile.path) == true)
    }

    @Test("WorkspaceTestHelpers creates workspace with config")
    func testCreateWorkspaceWithConfig() throws {
        let workspace = try WorkspaceTestHelpers.createWorkspaceWithConfig()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let configFile = workspace.appendingPathComponent(".swiftlint.yml")
        #expect(FileManager.default.fileExists(atPath: configFile.path) == true)
    }
}
