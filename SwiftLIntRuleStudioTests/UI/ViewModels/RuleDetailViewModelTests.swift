//
//  RuleDetailViewModelTests.swift
//  SwiftLIntRuleStudioTests
//
//  Unit tests for RuleDetailViewModel
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

// RuleDetailViewModel and YAMLConfigurationEngine are @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
struct RuleDetailViewModelTests {
    
    // Helper to create YAMLConfigurationEngine on MainActor
    private func createYAMLConfigurationEngine(configPath: URL) async -> YAMLConfigurationEngine {
        return await MainActor.run {
            YAMLConfigurationEngine(configPath: configPath)
        }
    }
    
    // Helper to create RuleDetailViewModel on MainActor
    private func createRuleDetailViewModel(
        rule: Rule,
        yamlEngine: YAMLConfigurationEngine? = nil,
        workspaceManager: WorkspaceManager? = nil
    ) async -> RuleDetailViewModel {
        return await MainActor.run {
            RuleDetailViewModel(rule: rule, yamlEngine: yamlEngine, workspaceManager: workspaceManager)
        }
    }
    
    private func createTempConfigFile(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let configFile = tempDir.appendingPathComponent(".swiftlint.yml")
        if !content.isEmpty {
            try content.write(to: configFile, atomically: true, encoding: .utf8)
        }
        
        return configFile
    }
    
    private func cleanupTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
    
    // MARK: - Initialization Tests
    
    @Test("RuleDetailViewModel initializes with rule state")
    func testInitialization() async throws {
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule)
        
        let (ruleId, isEnabled, severity, pendingChanges) = await MainActor.run {
            return (viewModel.rule.id, viewModel.isEnabled, viewModel.severity, viewModel.pendingChanges)
        }
        
        #expect(ruleId == "test_rule")
        #expect(isEnabled == false) // Rule starts disabled
        #expect(severity == nil)
        #expect(pendingChanges == nil)
    }
    
    @Test("RuleDetailViewModel initializes with opt-in rule")
    func testInitializationOptInRule() async throws {
        let rule = createTestRule(id: "opt_in_rule", isOptIn: true)
        let viewModel = await createRuleDetailViewModel(rule: rule)
        
        let (isOptIn, isEnabled) = await MainActor.run {
            return (viewModel.rule.isOptIn, viewModel.isEnabled)
        }
        
        #expect(isOptIn == true)
        #expect(isEnabled == false) // Opt-in rules start disabled
    }
    
    // MARK: - Configuration Loading Tests
    
    @Test("RuleDetailViewModel loads configuration from workspace")
    func testLoadConfiguration() async throws {
        // Create a config file with a rule
        let configContent = """
        rules:
          test_rule:
            enabled: true
            severity: error
        """
        let configPath = try createTempConfigFile(content: configContent)
        defer { cleanupTempFile(configPath) }
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        try await MainActor.run {
            try viewModel.loadConfiguration()
        }
        
        let (isEnabled, severity) = await MainActor.run {
            return (viewModel.isEnabled, viewModel.severity)
        }
        
        #expect(isEnabled == true)
        #expect(severity == .error)
    }
    
    @Test("RuleDetailViewModel loads default state when rule not in config")
    func testLoadConfigurationRuleNotInConfig() async throws {
        // Create empty config
        let configContent = "rules: {}"
        let configPath = try createTempConfigFile(content: configContent)
        defer { cleanupTempFile(configPath) }
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        try await MainActor.run {
            try viewModel.loadConfiguration()
        }
        
        // Non-opt-in rules are enabled by default
        let isEnabled = await MainActor.run { viewModel.isEnabled }
        #expect(isEnabled == true)
    }
    
    @Test("RuleDetailViewModel loads disabled state for opt-in rule not in config")
    func testLoadConfigurationOptInRuleNotInConfig() async throws {
        // Create empty config
        let configContent = "rules: {}"
        let configPath = try createTempConfigFile(content: configContent)
        defer { cleanupTempFile(configPath) }
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "opt_in_rule", isOptIn: true)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        try await MainActor.run {
            try viewModel.loadConfiguration()
        }
        
        // Opt-in rules are disabled by default
        let isEnabled = await MainActor.run { viewModel.isEnabled }
        #expect(isEnabled == false)
    }
    
    @Test("RuleDetailViewModel handles missing config file")
    func testLoadConfigurationMissingFile() async throws {
        // Don't create config file
        let configPath = try createTempConfigFile(content: "")
        defer { cleanupTempFile(configPath) }
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        // Should not throw, should use defaults
        try await MainActor.run {
            try viewModel.loadConfiguration()
        }
        
        let isEnabled = await MainActor.run { viewModel.isEnabled }
        #expect(isEnabled == true) // Default for non-opt-in
    }
    
    // MARK: - State Update Tests
    
    @Test("RuleDetailViewModel tracks pending changes when enabled state changes")
    func testUpdateEnabledTracksChanges() async throws {
        let configPath = try createTempConfigFile(content: "")
        defer { cleanupTempFile(configPath) }
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        // Load initial config (will set defaults)
        try await MainActor.run {
            try viewModel.loadConfiguration()
        }
        
        // Change enabled state
        await MainActor.run {
            viewModel.updateEnabled(false)
        }
        
        let (hasPendingChanges, enabled) = await MainActor.run {
            return (viewModel.pendingChanges != nil, viewModel.pendingChanges?.enabled)
        }
        
        #expect(hasPendingChanges == true)
        #expect(enabled == false)
    }
    
    @Test("RuleDetailViewModel tracks pending changes when severity changes")
    func testUpdateSeverityTracksChanges() async throws {
        // Create config with rule
        let configContent = """
        rules:
          test_rule:
            enabled: true
            severity: warning
        """
        let configPath = try createTempConfigFile(content: configContent)
        defer { cleanupTempFile(configPath) }
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        try await MainActor.run {
            try viewModel.loadConfiguration()
        }
        
        // Change severity
        await MainActor.run {
            viewModel.updateSeverity(.error)
        }
        
        let (hasPendingChanges, severity) = await MainActor.run {
            return (viewModel.pendingChanges != nil, viewModel.pendingChanges?.severity)
        }
        
        #expect(hasPendingChanges == true)
        #expect(severity == .error)
    }
    
    @Test("RuleDetailViewModel clears pending changes when reverted")
    func testPendingChangesClearedOnRevert() async throws {
        let configContent = """
        rules:
          test_rule:
            enabled: true
            severity: warning
        """
        let configPath = try createTempConfigFile(content: configContent)
        defer { cleanupTempFile(configPath) }
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        try await MainActor.run {
            try viewModel.loadConfiguration()
        }
        
        // Make a change
        await MainActor.run {
            viewModel.updateEnabled(false)
        }
        let hasPendingAfterChange = await MainActor.run { viewModel.pendingChanges != nil }
        #expect(hasPendingAfterChange == true)
        
        // Revert
        await MainActor.run {
            viewModel.updateEnabled(true)
        }
        let hasPendingAfterRevert = await MainActor.run { viewModel.pendingChanges == nil }
        #expect(hasPendingAfterRevert == true)
    }
    
    // MARK: - Diff Generation Tests
    
    @Test("RuleDetailViewModel generates diff for new rule")
    func testGenerateDiffNewRule() async throws {
        // Empty config
        let configContent = "rules: {}"
        let configPath = try createTempConfigFile(content: configContent)
        defer { cleanupTempFile(configPath) }
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "new_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        try await MainActor.run {
            try viewModel.loadConfiguration()
        }
        
        // Enable the rule
        await MainActor.run {
            viewModel.updateEnabled(true)
            viewModel.updateSeverity(.error)
        }
        
        let (diff, hasNewRule) = await MainActor.run {
            let diff = viewModel.generateDiff()
            return (diff, diff?.addedRules.contains("new_rule") == true)
        }
        
        #expect(diff != nil)
        #expect(hasNewRule == true)
    }
    
    @Test("RuleDetailViewModel generates diff for modified rule")
    func testGenerateDiffModifiedRule() async throws {
        let configContent = """
        rules:
          test_rule:
            enabled: true
            severity: warning
        """
        let configPath = try createTempConfigFile(content: configContent)
        defer { cleanupTempFile(configPath) }
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        try await MainActor.run {
            try viewModel.loadConfiguration()
        }
        
        // Change severity
        await MainActor.run {
            viewModel.updateSeverity(.error)
        }
        
        let (diff, hasModifiedRule) = await MainActor.run {
            let diff = viewModel.generateDiff()
            return (diff, diff?.modifiedRules.contains("test_rule") == true)
        }
        
        #expect(diff != nil)
        #expect(hasModifiedRule == true)
    }
    
    @Test("RuleDetailViewModel generates diff for disabled rule")
    func testGenerateDiffDisabledRule() async throws {
        let configContent = """
        rules:
          test_rule:
            enabled: true
            severity: warning
        """
        let configPath = try createTempConfigFile(content: configContent)
        defer { cleanupTempFile(configPath) }
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        try await MainActor.run {
            try viewModel.loadConfiguration()
        }
        
        // Disable the rule
        await MainActor.run {
            viewModel.updateEnabled(false)
        }
        
        let (diff, hasModifiedRule) = await MainActor.run {
            let diff = viewModel.generateDiff()
            return (diff, diff?.modifiedRules.contains("test_rule") == true)
        }
        
        #expect(diff != nil)
        #expect(hasModifiedRule == true)
    }
    
    // MARK: - Save Configuration Tests
    
    @Test("RuleDetailViewModel saves enabled rule to config")
    func testSaveConfigurationEnableRule() async throws {
        // Start with empty config
        let configContent = "rules: {}"
        let configPath = try createTempConfigFile(content: configContent)
        defer { cleanupTempFile(configPath) }
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        try await MainActor.run {
            try viewModel.loadConfiguration()
        }
        
        // Enable and set severity
        await MainActor.run {
            viewModel.updateEnabled(true)
            viewModel.updateSeverity(.error)
        }
        
        // Save
        try await MainActor.run {
            try viewModel.saveConfiguration()
        }
        
        // Verify saved - extract all values inside MainActor context
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
        // Start with enabled rule
        let configContent = """
        rules:
          test_rule:
            enabled: true
            severity: warning
        """
        let configPath = try createTempConfigFile(content: configContent)
        defer { cleanupTempFile(configPath) }
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        try await MainActor.run {
            try viewModel.loadConfiguration()
        }
        
        // Disable
        await MainActor.run {
            viewModel.updateEnabled(false)
        }
        
        // Save
        try await MainActor.run {
            try viewModel.saveConfiguration()
        }
        
        // Verify saved - extract values inside MainActor context
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
        let configPath = try createTempConfigFile(content: configContent)
        defer { cleanupTempFile(configPath) }
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        try await MainActor.run {
            try viewModel.loadConfiguration()
        }
        
        // Change severity
        await MainActor.run {
            viewModel.updateSeverity(.error)
        }
        
        // Save
        try await MainActor.run {
            try viewModel.saveConfiguration()
        }
        
        // Verify saved
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
        let configPath = try createTempConfigFile(content: configContent)
        defer { cleanupTempFile(configPath) }
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        try await MainActor.run {
            try viewModel.loadConfiguration()
        }
        
        await MainActor.run {
            viewModel.updateSeverity(.error)
        }
        try await MainActor.run {
            try viewModel.saveConfiguration()
        }
        
        // Check for backup file - backup files have format: .swiftlint.yml.{timestamp}.backup
        let backupDir = configPath.deletingLastPathComponent()
        let backupFiles = try FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil)
            .filter {
                let name = $0.lastPathComponent
                return name.hasPrefix(".swiftlint.yml.") && name.hasSuffix(".backup")
            }
        
        #expect(backupFiles.count >= 1, "Expected at least one backup file, found \(backupFiles.count)")
    }
    
    // MARK: - Error Handling Tests
    
    @Test("RuleDetailViewModel throws error when saving without workspace")
    func testSaveConfigurationNoWorkspace() async throws {
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule) // No yamlEngine
        
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
        // Test the case where the directory doesn't exist
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let invalidPath = tempDir.appendingPathComponent("nonexistent").appendingPathComponent(".swiftlint.yml")
        let invalidEngine = await createYAMLConfigurationEngine(configPath: invalidPath)
        
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: invalidEngine)
        
        await MainActor.run {
            viewModel.updateEnabled(true)
        }
        
        // Should throw an error when trying to save
        do {
            try await MainActor.run {
                try viewModel.saveConfiguration()
            }
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            // Expected - directory doesn't exist
            #expect(error is CocoaError || error is YAMLConfigError)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestRule(id: String, isOptIn: Bool) -> Rule {
        Rule(
            id: id,
            name: id.replacingOccurrences(of: "_", with: " ").capitalized,
            description: "Test rule description",
            category: .style,
            isOptIn: isOptIn,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: false,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: .warning,
            markdownDocumentation: nil
        )
    }
}
