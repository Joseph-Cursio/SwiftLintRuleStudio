//
//  WorkspaceManagerConfigTests.swift
//  SwiftLintRuleStudioTests
//
//  Config file tests for WorkspaceManager
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

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

        #expect(isMissing)
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

    @Test("WorkspaceManager flags a config SwiftLint rejects for only_rules beside opt_in_rules")
    func testCheckConfigRuleListsFlagsConflict() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        let configPath = workspace.appendingPathComponent(".swiftlint.yml")

        let problems = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace)
            var problems: [ConfigRuleListsProblem?] = []
            for content in [
                "only_rules:\n  - force_cast\nopt_in_rules:\n  - empty_count\n",
                "only_rules:\n  - force_cast\n  - unused_import\nanalyzer_rules:\n  - unused_import\n",
                "only_rules:\n  - force_cast\n"
            ] {
                try content.write(to: configPath, atomically: true, encoding: .utf8)
                manager.checkConfigRuleLists()
                problems.append(manager.configRuleListsProblem)
            }
            try FileManager.default.removeItem(at: configPath)
            manager.checkConfigRuleLists()
            problems.append(manager.configRuleListsProblem)
            return problems
        }

        #expect(problems == [.onlyRulesConflict, .analyzerRulesInOnlyRules(["unused_import"]), nil, nil])
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
        #expect(exists)
    }

    @Test("Default config excludes build dirs at any depth via ** globs")
    func testDefaultConfigGlobsNestedBuildDirs() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let content = try await WorkspaceManagerTestHelpers.withWorkspaceManager { manager in
            try manager.openWorkspace(at: workspace)
            let configPath = try manager.createDefaultConfigFile()
            return try String(contentsOf: #require(configPath), encoding: .utf8)
        }

        // Nestable build/metadata dirs use a quoted ** glob so they match nested
        // SPM packages (e.g. Core/.build), not just the workspace-root dir.
        #expect(content.contains("\"**/.build\""))
        #expect(content.contains("\"**/.swiftpm\""))
        #expect(content.contains("\"**/xcuserdata\""))
        // A bare top-level-only entry must NOT be present for .build.
        #expect(content.contains("- .build\n") == false)
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

        #expect(isMissing)
    }
}
