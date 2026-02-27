//
//  RuleDetailViewModelWorkspaceIntegrationTests.swift
//  SwiftLIntRuleStudioTests
//
//  WorkspaceManager integration tests
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct RuleDetailVMWorkspaceIntegrationTests {
    @Test("RuleDetailViewModel works with WorkspaceManager")
    func testRuleDetailViewModelWithWorkspaceManager() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let workspaceManager = await RuleDetailVMIntegrationHelpers.createWorkspaceManager()
        let (_, configPath) = try await openWorkspaceAndConfig(
            workspaceManager: workspaceManager,
            at: tempDir
        )

        let yamlEngine = await RuleDetailVMIntegrationHelpers.createYAMLConfigurationEngine(
            configPath: configPath
        )
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailVMIntegrationHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine,
            workspaceManager: workspaceManager
        )

        try await Task { @MainActor in
            try viewModel.loadConfiguration()
            viewModel.updateEnabled(true)
            viewModel.updateSeverity(.error)
            try viewModel.saveConfiguration()
        }.value

        #expect(FileManager.default.fileExists(atPath: configPath.path))

        try await Task { @MainActor in
            try yamlEngine.load()
        }.value
        let (enabled, severity) = await MainActor.run {
            let config = yamlEngine.getConfig()
            return (config.rules["test_rule"]?.enabled, config.rules["test_rule"]?.severity)
        }
        #expect(enabled == true)
        #expect(severity == .error)
    }

    @Test("RuleDetailViewModel handles workspace switch")
    func testRuleDetailViewModelHandlesWorkspaceSwitch() async throws {
        let config1 = """
        rules:
          rule_1:
            enabled: true
            severity: warning
        """
        let config2 = """
        rules:
          rule_2:
            enabled: false
        """
        let (tempDir1, configPath1) = try createWorkspaceWithConfig(config1)
        let (tempDir2, configPath2) = try createWorkspaceWithConfig(config2)
        defer {
            WorkspaceTestHelpers.cleanupWorkspace(tempDir1)
            WorkspaceTestHelpers.cleanupWorkspace(tempDir2)
        }

        let workspaceManager = await RuleDetailVMIntegrationHelpers.createWorkspaceManager()

        let workspace1 = try await openWorkspace(
            workspaceManager: workspaceManager,
            at: tempDir1
        )
        let viewModel1 = try await makeViewModelAndLoadConfig(
            ruleId: "rule_1",
            configPath: configPath1,
            workspaceManager: workspaceManager
        )
        await assertRuleState(
            viewModel1,
            enabled: true,
            severity: .warning
        )

        _ = try await openWorkspace(
            workspaceManager: workspaceManager,
            at: tempDir2
        )
        let viewModel2 = try await makeViewModelAndLoadConfig(
            ruleId: "rule_2",
            configPath: configPath2,
            workspaceManager: workspaceManager
        )
        await assertRuleState(
            viewModel2,
            enabled: false,
            severity: nil
        )
        await assertWorkspacePath(workspace1, matches: tempDir1)
    }

    private func openWorkspaceAndConfig(
        workspaceManager: WorkspaceManager,
        at url: URL
    ) async throws -> (Workspace, URL) {
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: url)
            let workspace = try #require(workspaceManager.currentWorkspace)
            guard let configPath = workspace.configPath else {
                throw TestError("Workspace should have config path")
            }
            return (workspace, configPath)
        }
    }

    private func openWorkspace(
        workspaceManager: WorkspaceManager,
        at url: URL
    ) async throws -> Workspace {
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: url)
            return try #require(workspaceManager.currentWorkspace)
        }
    }

    private func makeViewModel(
        ruleId: String,
        configPath: URL,
        workspaceManager: WorkspaceManager
    ) async -> RuleDetailViewModel {
        let yamlEngine = await RuleDetailVMIntegrationHelpers.createYAMLConfigurationEngine(
            configPath: configPath
        )
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: ruleId, isOptIn: false)
        return await RuleDetailVMIntegrationHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine,
            workspaceManager: workspaceManager
        )
    }

    private func makeViewModelAndLoadConfig(
        ruleId: String,
        configPath: URL,
        workspaceManager: WorkspaceManager
    ) async throws -> RuleDetailViewModel {
        let viewModel = await makeViewModel(
            ruleId: ruleId,
            configPath: configPath,
            workspaceManager: workspaceManager
        )
        try await Task { @MainActor in
            try viewModel.loadConfiguration()
        }.value
        return viewModel
    }

    private func assertRuleState(
        _ viewModel: RuleDetailViewModel,
        enabled: Bool,
        severity: Severity?
    ) async {
        let (isEnabled, currentSeverity) = await MainActor.run {
            (viewModel.isEnabled, viewModel.severity)
        }
        #expect(isEnabled == enabled)
        #expect(currentSeverity == severity)
    }

    private func assertWorkspacePath(_ workspace: Workspace, matches expected: URL) async {
        let workspacePath = await MainActor.run { workspace.path }
        #expect(workspacePath == expected)
    }

    private func createWorkspaceWithConfig(_ content: String) throws -> (URL, URL) {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        let configPath = try RuleDetailVMIntegrationHelpers.createConfigFile(
            in: tempDir,
            content: content
        )
        return (tempDir, configPath)
    }
}

private struct TestError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
