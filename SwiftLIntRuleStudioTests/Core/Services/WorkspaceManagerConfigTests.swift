//
//  WorkspaceManagerConfigTests.swift
//  SwiftLIntRuleStudioTests
//
//  Config file tests for WorkspaceManager
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct WorkspaceManagerConfigTests {
    @Test("WorkspaceManager checkConfigFileExists clears missing state without workspace")
    func testCheckConfigFileExistsWithoutWorkspace() async throws {
        let isMissing = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            manager.configFileMissing = true
            manager.checkConfigFileExists()
            return manager.configFileMissing
        }

        #expect(isMissing == false)
    }

    @Test("WorkspaceManager detects missing config file")
    func testDetectMissingConfigFile() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let isMissing = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace)
            manager.checkConfigFileExists()
            return manager.configFileMissing
        }

        #expect(isMissing == true)
    }

    @Test("WorkspaceManager detects existing config file")
    func testDetectExistingConfigFile() async throws {
        let workspace = try WorkspaceTestHelpers.createWorkspaceWithConfig()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let isMissing = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace)
            manager.checkConfigFileExists()
            return manager.configFileMissing
        }

        #expect(isMissing == false)
    }

    @Test("WorkspaceManager creates default config file")
    func testCreateDefaultConfigFile() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let (configPath, exists) = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace)
            let configPath = try manager.createDefaultConfigFile()
            let exists = configPath.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            return (configPath, exists)
        }

        #expect(configPath != nil)
        #expect(exists == true)
    }

    @Test("WorkspaceManager does not overwrite existing config file")
    func testDoesNotOverwriteConfigFile() async throws {
        let workspace = try WorkspaceTestHelpers.createWorkspaceWithConfig()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let originalContent = try String(
            contentsOf: workspace.appendingPathComponent(".swiftlint.yml"),
            encoding: .utf8
        )

        let savedContent = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace)
            _ = try manager.createDefaultConfigFile()
            return try String(
                contentsOf: workspace.appendingPathComponent(".swiftlint.yml"),
                encoding: .utf8
            )
        }

        #expect(savedContent == originalContent)
    }

    @Test("WorkspaceManager updates configFileMissing when workspace closes")
    func testConfigFileMissingOnClose() async throws {
        let workspace = try WorkspaceTestHelpers.createWorkspaceWithConfig()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let isMissing = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace)
            manager.closeWorkspace()
            return manager.configFileMissing
        }

        #expect(isMissing == false)
    }

    @Test("WorkspaceManager checks config file on workspace change")
    func testCheckConfigFileOnWorkspaceChange() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let isMissing = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace)
            manager.checkConfigFileExists()
            return manager.configFileMissing
        }

        #expect(isMissing == true)
    }
}
