//
//  RuleDetailViewModelSaveTests.swift
//  SwiftLIntRuleStudioTests
//
//  Save tests for RuleDetailViewModel
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct RuleDetailViewModelSaveTests {
    @Test("RuleDetailViewModel saves enabled rule to config")
    func testSaveConfigurationEnableRule() async throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: "rules: {}")
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        await MainActor.run {
            viewModel.updateEnabled(true)
            viewModel.updateSeverity(.error)
        }

        try await MainActor.run {
            try viewModel.saveConfiguration()
        }

        let snapshot = try await MainActor.run {
            try yamlEngine.load()
            let config = yamlEngine.getConfig()
            let ruleConfig = config.rules["test_rule"]
            return (
                hasRule: ruleConfig != nil,
                isEnabled: ruleConfig?.enabled == true,
                severityMatch: ruleConfig?.severity == .error,
                pendingChangesCleared: viewModel.pendingChanges == nil
            )
        }

        #expect(snapshot.hasRule == true)
        #expect(snapshot.isEnabled == true)
        #expect(snapshot.severityMatch == true)
        #expect(snapshot.pendingChangesCleared == true)
    }

    @Test("RuleDetailViewModel saves disabled rule to config")
    func testSaveConfigurationDisableRule() async throws {
        let configContent = """
        rules:
          test_rule:
            enabled: true
            severity: warning
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        await MainActor.run {
            viewModel.updateEnabled(false)
        }

        try await MainActor.run {
            try viewModel.saveConfiguration()
        }

        let (hasRule, isEnabled) = try await MainActor.run {
            try yamlEngine.load()
            let config = yamlEngine.getConfig()
            let ruleConfig = config.rules["test_rule"]
            return (ruleConfig != nil, ruleConfig?.enabled == false)
        }

        #expect(hasRule == true)
        #expect(isEnabled == true)
    }

    @Test("RuleDetailViewModel saves severity change")
    func testSaveConfigurationSeverityChange() async throws {
        let configContent = """
        rules:
          test_rule:
            enabled: true
            severity: warning
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        await MainActor.run {
            viewModel.updateSeverity(.error)
        }

        try await MainActor.run {
            try viewModel.saveConfiguration()
        }

        let severity = try await MainActor.run {
            try yamlEngine.load()
            let config = yamlEngine.getConfig()
            return config.rules["test_rule"]?.severity
        }

        #expect(severity == .error)
    }

    @Test("RuleDetailViewModel creates backup when saving")
    func testSaveConfigurationCreatesBackup() async throws {
        let configContent = """
        rules:
          test_rule:
            enabled: true
        """
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: configContent)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }

        let yamlEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: configPath)
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await MainActor.run {
            try viewModel.loadConfiguration()
        }

        await MainActor.run {
            viewModel.updateSeverity(.error)
        }
        try await MainActor.run {
            try viewModel.saveConfiguration()
        }

        let backupDir = configPath.deletingLastPathComponent()
        let backupFiles = try FileManager.default.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: nil
        )
        .filter {
            let name = $0.lastPathComponent
            return name.hasPrefix(".swiftlint.yml.") && name.hasSuffix(".backup")
        }

        #expect(backupFiles.count >= 1, "Expected at least one backup file, found \(backupFiles.count)")
    }

    @Test("RuleDetailViewModel throws error when saving without workspace")
    func testSaveConfigurationNoWorkspace() async throws {
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(rule: rule)

        await MainActor.run {
            viewModel.updateEnabled(true)
        }

        await #expect(throws: RuleConfigurationError.noWorkspace) {
            try await MainActor.run {
                try viewModel.saveConfiguration()
            }
        }
    }

    @Test("RuleDetailViewModel handles save errors gracefully")
    func testSaveConfigurationErrorHandling() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let invalidPath = tempDir
            .appendingPathComponent("nonexistent")
            .appendingPathComponent(".swiftlint.yml")
        let invalidEngine = await RuleDetailViewModelTestHelpers.createYAMLConfigurationEngine(configPath: invalidPath)

        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: invalidEngine
        )

        await MainActor.run {
            viewModel.updateEnabled(true)
        }

        do {
            try await MainActor.run {
                try viewModel.saveConfiguration()
            }
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is CocoaError || error is YAMLConfigError)
        }
    }
}
