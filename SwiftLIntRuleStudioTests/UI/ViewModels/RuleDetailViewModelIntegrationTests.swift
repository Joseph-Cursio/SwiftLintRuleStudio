//
//  RuleDetailViewModelIntegrationTests.swift
//  SwiftLIntRuleStudioTests
//
//  Integration tests for RuleDetailViewModel with other components
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// RuleDetailViewModel, YAMLConfigurationEngine, and WorkspaceManager are @MainActor
// but we'll use await MainActor.run { } inside tests to allow parallel test execution
struct RuleDetailViewModelIntegrationTests {
    
    // MARK: - Test Helpers
    
    // Helper to create RuleDetailViewModel on MainActor
    private func createRuleDetailViewModel(
        rule: Rule,
        yamlEngine: YAMLConfigurationEngine? = nil,
        workspaceManager: WorkspaceManager? = nil
    ) async -> RuleDetailViewModel {
        // Capture with nonisolated(unsafe) to bypass Sendable check for test mocks
        nonisolated(unsafe) let engineCapture = yamlEngine
        nonisolated(unsafe) let managerCapture = workspaceManager
        return await MainActor.run {
            RuleDetailViewModel(rule: rule, yamlEngine: engineCapture, workspaceManager: managerCapture)
        }
    }
    
    // Helper to create YAMLConfigurationEngine on MainActor
    private func createYAMLConfigurationEngine(configPath: URL) async -> YAMLConfigurationEngine {
        return await MainActor.run {
            YAMLConfigurationEngine(configPath: configPath)
        }
    }
    
    // Helper to create WorkspaceManager on MainActor
    private func createWorkspaceManager() async -> WorkspaceManager {
        return await MainActor.run {
            WorkspaceManager.createForTesting(testName: #function)
        }
    }
    
    // Use WorkspaceTestHelpers for creating valid Swift workspaces
    // This ensures WorkspaceManager validation passes
    
    private func createConfigFile(in directory: URL, content: String) throws -> URL {
        let configPath = directory.appendingPathComponent(".swiftlint.yml")
        try content.write(to: configPath, atomically: true, encoding: .utf8)
        return configPath
    }
    
    private func createTestRule(id: String, isOptIn: Bool = false) -> Rule {
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
    
    // MARK: - RuleDetailViewModel + YAMLConfigurationEngine Integration
    
    @Test("RuleDetailViewModel loads and saves configuration through YAMLConfigurationEngine")
    func testRuleDetailViewModelWithYAMLConfigurationEngine() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        // Create initial config
        let initialConfig = """
        rules:
          test_rule:
            enabled: true
            severity: warning
        """
        let configPath = try createConfigFile(in: tempDir, content: initialConfig)
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        // Load configuration
        try await Task { @MainActor in
            try viewModel.loadConfiguration()
        }.value
        
        let (isEnabled, severity) = await MainActor.run {
            return (viewModel.isEnabled, viewModel.severity)
        }
        #expect(isEnabled == true)
        #expect(severity == .warning)
        
        // Change configuration
        await MainActor.run {
            viewModel.updateSeverity(.error)
        }
        
        // Save
        try await Task { @MainActor in
            try await viewModel.saveConfiguration()
        }.value
        
        // Verify file was updated
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
        
        // No config file exists
        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        
        let rule = createTestRule(id: "new_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        // Load (should use defaults)
        try await Task { @MainActor in
            try viewModel.loadConfiguration()
        }.value
        let isEnabled = await MainActor.run {
            viewModel.isEnabled
        }
        #expect(isEnabled == true) // Non-opt-in rules enabled by default
        
        // Enable and set severity
        await MainActor.run {
            viewModel.updateSeverity(.error)
        }
        
        // Save
        try await Task { @MainActor in
            try await viewModel.saveConfiguration()
        }.value
        
        // Verify file was created
        #expect(FileManager.default.fileExists(atPath: configPath.path))
        
        // Verify content
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
        
        // Create config with multiple rules
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
        let configPath = try createConfigFile(in: tempDir, content: initialConfig)
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        
        // Modify rule_1
        let rule = createTestRule(id: "rule_1", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        try await Task { @MainActor in
            try viewModel.loadConfiguration()
            viewModel.updateSeverity(.error)
            try await viewModel.saveConfiguration()
        }.value
        
        // Verify all rules are still present
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
    
    // MARK: - RuleDetailViewModel + WorkspaceManager Integration
    
    @Test("RuleDetailViewModel works with WorkspaceManager")
    func testRuleDetailViewModelWithWorkspaceManager() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        let workspaceManager = await createWorkspaceManager()
        let (workspace, configPath) = try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
            let workspace = try #require(workspaceManager.currentWorkspace)
            guard let configPath = workspace.configPath else {
                throw TestError("Workspace should have config path")
            }
            return (workspace, configPath)
        }
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine,
            workspaceManager: workspaceManager
        )
        
        // Load and save
        try await Task { @MainActor in
            try viewModel.loadConfiguration()
            viewModel.updateEnabled(true)
            viewModel.updateSeverity(.error)
            try await viewModel.saveConfiguration()
        }.value
        
        // Verify config was saved to workspace
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
        let tempDir1 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        let tempDir2 = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer {
            WorkspaceTestHelpers.cleanupWorkspace(tempDir1)
            WorkspaceTestHelpers.cleanupWorkspace(tempDir2)
        }
        
        // Create configs in both workspaces
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
        let configPath1 = try createConfigFile(in: tempDir1, content: config1)
        let configPath2 = try createConfigFile(in: tempDir2, content: config2)
        
        let workspaceManager = await createWorkspaceManager()
        
        // Open first workspace
        let workspace1 = try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir1)
            return try #require(workspaceManager.currentWorkspace)
        }
        
        let yamlEngine1 = await createYAMLConfigurationEngine(configPath: configPath1)
        let rule1 = createTestRule(id: "rule_1", isOptIn: false)
        let viewModel1 = await createRuleDetailViewModel(
            rule: rule1,
            yamlEngine: yamlEngine1,
            workspaceManager: workspaceManager
        )
        
        try await Task { @MainActor in
            try viewModel1.loadConfiguration()
        }.value
        let (isEnabled1, severity1) = await MainActor.run {
            return (viewModel1.isEnabled, viewModel1.severity)
        }
        #expect(isEnabled1 == true)
        #expect(severity1 == .warning)
        
        // Switch to second workspace
        let workspace2 = try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir2)
            return try #require(workspaceManager.currentWorkspace)
        }
        
        let yamlEngine2 = await createYAMLConfigurationEngine(configPath: configPath2)
        let rule2 = createTestRule(id: "rule_2", isOptIn: false)
        let viewModel2 = await createRuleDetailViewModel(
            rule: rule2,
            yamlEngine: yamlEngine2,
            workspaceManager: workspaceManager
        )
        
        try await Task { @MainActor in
            try viewModel2.loadConfiguration()
        }.value
        let isEnabled2 = await MainActor.run {
            viewModel2.isEnabled
        }
        #expect(isEnabled2 == false)
    }
    
    // MARK: - Notification System Integration
    
    @Test("RuleDetailViewModel posts notification when configuration is saved")
    func testRuleDetailViewModelPostsNotification() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        let configPath = try createConfigFile(in: tempDir, content: "rules: {}")
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        var notificationReceived = false
        var receivedRuleId: String?
        
        // Set up notification observer
        let observer = NotificationCenter.default.addObserver(
            forName: .ruleConfigurationDidChange,
            object: nil,
            queue: .main
        ) { notification in
            notificationReceived = true
            receivedRuleId = notification.userInfo?["ruleId"] as? String
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        
        // Load, modify, and save
        try await Task { @MainActor in
            try viewModel.loadConfiguration()
            viewModel.updateEnabled(true)
            viewModel.updateSeverity(.error)
            try await viewModel.saveConfiguration()
        }.value
        
        // Give notification time to post
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        #expect(notificationReceived == true)
        #expect(receivedRuleId == "test_rule")
    }
    
    // MARK: - Full Workflow Integration Tests
    
    @Test("Complete workflow: open workspace -> configure rule -> save -> verify")
    func testCompleteRuleConfigurationWorkflow() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        // Step 1: Create workspace with initial config
        let initialConfig = """
        rules:
          existing_rule:
            enabled: true
            severity: warning
        """
        let configPath = try createConfigFile(in: tempDir, content: initialConfig)
        
        let workspaceManager = await createWorkspaceManager()
        let workspace = try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
            return try #require(workspaceManager.currentWorkspace)
        }
        
        // Step 2: Create ViewModel for a new rule
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        let rule = createTestRule(id: "new_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine,
            workspaceManager: workspaceManager
        )
        
        // Step 3: Load configuration (rule not in config, uses defaults)
        try await Task { @MainActor in
            try viewModel.loadConfiguration()
        }.value
        let (isEnabled, pendingChanges1) = await MainActor.run {
            return (viewModel.isEnabled, viewModel.pendingChanges)
        }
        #expect(isEnabled == true) // Default for non-opt-in
        #expect(pendingChanges1 == nil)
        
        // Step 4: Configure rule
        await MainActor.run {
            viewModel.updateSeverity(.error)
        }
        let pendingChanges2 = await MainActor.run {
            viewModel.pendingChanges
        }
        #expect(pendingChanges2 != nil)
        
        // Step 5: Generate diff
        let (hasDiff, hasNewRule) = await MainActor.run {
            let diff = viewModel.generateDiff()
            return (diff != nil, diff?.addedRules.contains("new_rule") == true)
        }
        #expect(hasDiff == true)
        #expect(hasNewRule == true)
        
        // Step 6: Save configuration
        try await Task { @MainActor in
            try await viewModel.saveConfiguration()
        }.value
        let pendingChanges3 = await MainActor.run {
            viewModel.pendingChanges
        }
        #expect(pendingChanges3 == nil)
        
        // Step 7: Verify file was updated
        try await Task { @MainActor in
            try yamlEngine.load()
        }.value
        let (hasNewRuleInConfig, newRuleEnabled, newRuleSeverity, hasExistingRule, existingRuleEnabled, existingRuleSeverity) = await MainActor.run {
            let config = yamlEngine.getConfig()
            return (
                config.rules["new_rule"] != nil,
                config.rules["new_rule"]?.enabled,
                config.rules["new_rule"]?.severity,
                config.rules["existing_rule"] != nil,
                config.rules["existing_rule"]?.enabled,
                config.rules["existing_rule"]?.severity
            )
        }
        
        #expect(hasNewRuleInConfig == true)
        #expect(newRuleEnabled == true)
        #expect(newRuleSeverity == .error)
        
        // Step 8: Verify existing rule was preserved
        #expect(hasExistingRule == true)
        #expect(existingRuleEnabled == true)
        #expect(existingRuleSeverity == .warning)
    }
    
    @Test("Multiple rules configuration workflow")
    func testMultipleRulesConfigurationWorkflow() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        let configPath = try createConfigFile(in: tempDir, content: "rules: {}")
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        
        // Configure first rule
        let rule1 = createTestRule(id: "rule_1", isOptIn: false)
        let viewModel1 = await createRuleDetailViewModel(rule: rule1, yamlEngine: yamlEngine)
        
        try await Task { @MainActor in
            try viewModel1.loadConfiguration()
            viewModel1.updateEnabled(true)
            viewModel1.updateSeverity(.error)
            try await viewModel1.saveConfiguration()
        }.value
        
        // Configure second rule
        let rule2 = createTestRule(id: "rule_2", isOptIn: true)
        let viewModel2 = await createRuleDetailViewModel(rule: rule2, yamlEngine: yamlEngine)
        
        try await Task { @MainActor in
            try viewModel2.loadConfiguration()
            viewModel2.updateEnabled(true)
            viewModel2.updateSeverity(.warning)
            try await viewModel2.saveConfiguration()
        }.value
        
        // Verify both rules are in config
        try await Task { @MainActor in
            try yamlEngine.load()
        }.value
        let (hasRule1, rule1Enabled, rule1Severity, hasRule2, rule2Enabled, rule2Severity) = await MainActor.run {
            let config = yamlEngine.getConfig()
            return (
                config.rules["rule_1"] != nil,
                config.rules["rule_1"]?.enabled,
                config.rules["rule_1"]?.severity,
                config.rules["rule_2"] != nil,
                config.rules["rule_2"]?.enabled,
                config.rules["rule_2"]?.severity
            )
        }
        
        #expect(hasRule1 == true)
        #expect(rule1Enabled == true)
        #expect(rule1Severity == .error)
        
        #expect(hasRule2 == true)
        #expect(rule2Enabled == true)
        #expect(rule2Severity == .warning)
    }
    
    @Test("Rule configuration persists across workspace reload")
    func testRuleConfigurationPersistsAcrossReload() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        let yamlEngine = await createYAMLConfigurationEngine(configPath: configPath)
        
        // Configure rule
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        try await Task { @MainActor in
            try viewModel.loadConfiguration()
            viewModel.updateEnabled(true)
            viewModel.updateSeverity(.error)
            try await viewModel.saveConfiguration()
        }.value
        
        // Create new engine instance (simulating reload)
        let yamlEngine2 = await createYAMLConfigurationEngine(configPath: configPath)
        try await Task { @MainActor in
            try yamlEngine2.load()
        }.value
        let (hasTestRule, testRuleEnabled, testRuleSeverity) = await MainActor.run {
            let config = yamlEngine2.getConfig()
            return (config.rules["test_rule"] != nil, config.rules["test_rule"]?.enabled, config.rules["test_rule"]?.severity)
        }
        
        #expect(hasTestRule == true)
        #expect(testRuleEnabled == true)
        #expect(testRuleSeverity == .error)
        
        // Create new ViewModel and verify it loads the saved config
        let viewModel2 = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine2)
        try await Task { @MainActor in
            try viewModel2.loadConfiguration()
        }.value
        
        let (isEnabled, severity) = await MainActor.run {
            return (viewModel2.isEnabled, viewModel2.severity)
        }
        #expect(isEnabled == true)
        #expect(severity == .error)
    }
    
    // MARK: - Error Handling Integration
    
    @Test("RuleDetailViewModel handles invalid workspace gracefully")
    func testRuleDetailViewModelHandlesInvalidWorkspace() async throws {
        // Create ViewModel without workspace
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule) // No yamlEngine
        
        // Should not crash when loading
        try await Task { @MainActor in
            try viewModel.loadConfiguration() // Should return early
        }.value
        
        // Should throw error when saving
        await MainActor.run {
            viewModel.updateEnabled(true)
        }
        await #expect(throws: RuleConfigurationError.noWorkspace) {
            try await Task { @MainActor in
                try await viewModel.saveConfiguration()
            }.value
        }
    }
    
    @Test("RuleDetailViewModel handles config file errors gracefully")
    func testRuleDetailViewModelHandlesConfigFileErrors() async throws {
        // Create config in non-existent directory
        let invalidPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("nonexistent")
            .appendingPathComponent(".swiftlint.yml")
        
        let yamlEngine = await createYAMLConfigurationEngine(configPath: invalidPath)
        let rule = createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await createRuleDetailViewModel(rule: rule, yamlEngine: yamlEngine)
        
        // Load should work (creates empty config)
        try await Task { @MainActor in
            try viewModel.loadConfiguration()
        }.value
        
        // Save should fail
        await MainActor.run {
            viewModel.updateEnabled(true)
        }
        do {
            try await Task { @MainActor in
                try await viewModel.saveConfiguration()
            }.value
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            // Expected - directory doesn't exist
            #expect(error is CocoaError || error is YAMLConfigError)
        }
    }
}

// MARK: - Test Error Helper

struct TestError: Error, CustomStringConvertible {
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
    
    var description: String {
        message
    }
}


