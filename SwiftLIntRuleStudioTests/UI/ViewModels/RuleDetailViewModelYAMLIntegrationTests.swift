//
//  RuleDetailViewModelYAMLIntegrationTests.swift
//  SwiftLIntRuleStudioTests
//
//  Integration tests with YAMLConfigurationEngine
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct RuleDetailViewModelYAMLIntegrationTests {
    @Test("RuleDetailViewModel loads and saves configuration through YAMLConfigurationEngine")
    func testRuleDetailViewModelWithYAMLConfigurationEngine() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let initialConfig = """
        rules:
          test_rule:
            enabled: true
            severity: warning
        """
        let configPath = try RuleDetailVMIntegrationHelpers.createConfigFile(
            in: tempDir,
            content: initialConfig
        )
        let yamlEngine = await RuleDetailVMIntegrationHelpers.createYAMLConfigurationEngine(
            configPath: configPath
        )

        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailVMIntegrationHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await Task { @MainActor in
            try viewModel.loadConfiguration()
        }.value

        let (isEnabled, severity) = await MainActor.run {
            (viewModel.isEnabled, viewModel.severity)
        }
        #expect(isEnabled == true)
        #expect(severity == .warning)

        await MainActor.run {
            viewModel.updateSeverity(.error)
        }

        try await Task { @MainActor in
            try await viewModel.saveConfiguration()
        }.value

        try await Task { @MainActor in
            try yamlEngine.load()
        }.value
        let (savedSeverity, savedEnabled) = await MainActor.run {
            let config = yamlEngine.getConfig()
            let ruleConfig = config.rules["test_rule"]
            return (ruleConfig?.severity, ruleConfig?.enabled)
        }

        #expect(savedSeverity == .error)
        #expect(savedEnabled == true)
    }

    @Test("RuleDetailViewModel creates new config file when none exists")
    func testRuleDetailViewModelCreatesNewConfigFile() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        let yamlEngine = await RuleDetailVMIntegrationHelpers.createYAMLConfigurationEngine(
            configPath: configPath
        )

        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "new_rule", isOptIn: false)
        let viewModel = await RuleDetailVMIntegrationHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await Task { @MainActor in
            try viewModel.loadConfiguration()
        }.value

        let isEnabled = await MainActor.run { viewModel.isEnabled }
        #expect(isEnabled == true)

        await MainActor.run {
            viewModel.updateSeverity(.error)
        }

        try await Task { @MainActor in
            try await viewModel.saveConfiguration()
        }.value

        #expect(FileManager.default.fileExists(atPath: configPath.path))

        try await Task { @MainActor in
            try yamlEngine.load()
        }.value
        let (hasRuleConfig, enabled, severity) = await MainActor.run {
            let config = yamlEngine.getConfig()
            let ruleConfig = config.rules["new_rule"]
            return (ruleConfig != nil, ruleConfig?.enabled, ruleConfig?.severity)
        }

        #expect(hasRuleConfig == true)
        #expect(enabled == true)
        #expect(severity == .error)
    }

    @Test("RuleDetailViewModel preserves other rules when saving")
    func testRuleDetailViewModelPreservesOtherRules() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let initialConfig = """
        rules:
          rule_1:
            enabled: true
            severity: warning
          rule_2:
            enabled: false
          rule_3:
            enabled: true
            severity: error
        """
        let configPath = try RuleDetailVMIntegrationHelpers.createConfigFile(
            in: tempDir,
            content: initialConfig
        )
        let yamlEngine = await RuleDetailVMIntegrationHelpers.createYAMLConfigurationEngine(
            configPath: configPath
        )

        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "rule_1", isOptIn: false)
        let viewModel = await RuleDetailVMIntegrationHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        try await Task { @MainActor in
            try viewModel.loadConfiguration()
            viewModel.updateSeverity(.error)
            try await viewModel.saveConfiguration()
        }.value

        try await Task { @MainActor in
            try yamlEngine.load()
        }.value
        let (hasRule1, rule1Severity, hasRule2) = await MainActor.run {
            let config = yamlEngine.getConfig()
            return (config.rules["rule_1"] != nil, config.rules["rule_1"]?.severity, config.rules["rule_2"] != nil)
        }
        let (rule2Enabled, hasRule3, rule3Severity) = await MainActor.run {
            let config = yamlEngine.getConfig()
            return (config.rules["rule_2"]?.enabled, config.rules["rule_3"] != nil, config.rules["rule_3"]?.severity)
        }

        #expect(hasRule1 == true)
        #expect(rule1Severity == .error)
        #expect(hasRule2 == true)
        #expect(rule2Enabled == false)
        #expect(hasRule3 == true)
        #expect(rule3Severity == .error)
    }
}
