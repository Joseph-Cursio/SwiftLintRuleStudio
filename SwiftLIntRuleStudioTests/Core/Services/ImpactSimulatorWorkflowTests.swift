//
//  ImpactSimulatorWorkflowTests.swift
//  SwiftLIntRuleStudioTests
//
//  End-to-end workflow tests for impact simulation
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

// ImpactSimulator is @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
struct ImpactSimulatorWorkflowTests {
    
    // Helper to run ImpactSimulator operations on MainActor
    private func createImpactSimulator(swiftLintCLI: MockSwiftLintCLI) async -> ImpactSimulator {
        return await MainActor.run {
            ImpactSimulator(swiftLintCLI: swiftLintCLI)
        }
    }
    
    // MARK: - Test Helpers
    
    // Use WorkspaceTestHelpers for creating valid Swift workspaces
    // This ensures WorkspaceManager validation passes
    
    private func createSwiftFile(in directory: URL, name: String, content: String) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    private func createMockSwiftLintCLI(violations: [Violation] = []) async -> MockSwiftLintCLI {
        let mockCLI = MockSwiftLintCLI()

        let jsonArray = violations.map { violation -> [String: Any] in
            [
                "file": violation.filePath,
                "line": violation.line,
                "character": violation.column ?? 0,
                "severity": violation.severity.rawValue,
                "rule_id": violation.ruleID,
                "reason": violation.message
            ]
        }
        let jsonData = try? JSONSerialization.data(withJSONObject: jsonArray)

        // Set up handler to return violations
        await mockCLI.setLintCommandHandler { @Sendable _, _ in
            return jsonData ?? Data()
        }

        return mockCLI
    }
    
    // MARK: - End-to-End Workflow Tests
    
    @Test("Full workflow: discover safe rules and enable them")
    func testFullWorkflowDiscoverAndEnable() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        // Create Swift files
        _ = try createSwiftFile(in: tempDir, name: "Test.swift", content: "let x = 1\n")
        
        let configPath = try writeDisabledRulesConfig(in: tempDir)
        let workspace = Workspace(path: tempDir)
        let mockCLI = MockSwiftLintCLI()
        
        await configureMockCLIForSafeRuleDiscovery(mockCLI)
        
        let simulator = await createImpactSimulator(swiftLintCLI: mockCLI)
        
        // Discover safe rules
        let disabledRuleIds = ["safe_rule_1", "safe_rule_2", "unsafe_rule"]
        let safeRuleIds = try await simulator.findSafeRules(
            workspace: workspace,
            baseConfigPath: configPath,
            disabledRuleIds: disabledRuleIds
        )
        
        #expect(safeRuleIds.count == 2)
        #expect(safeRuleIds.contains("safe_rule_1"))
        #expect(safeRuleIds.contains("safe_rule_2"))
        #expect(!safeRuleIds.contains("unsafe_rule"))
        
        let ruleEnablement = try await enableRules(safeRuleIds, configPath: configPath)
        assertRuleEnablement(ruleEnablement)
        
        // At minimum, verify the save operation completed
        #expect(FileManager.default.fileExists(atPath: configPath.path))
    }
    
    @Test("Workflow: simulate rule before enabling")
    func testSimulateBeforeEnable() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        _ = try createSwiftFile(in: tempDir, name: "Test.swift", content: "let x = 1\n")
        
        let workspace = Workspace(path: tempDir)
        let mockCLI = await createMockSwiftLintCLI(violations: [])
        let simulator = await createImpactSimulator(swiftLintCLI: mockCLI)

        // Simulate a rule
        let result = try await simulator.simulateRule(
            ruleId: "test_rule",
            workspace: workspace,
            baseConfigPath: nil
        )

        #expect(result.isSafe == true)
        #expect(result.violationCount == 0)
        
        // Now enable it
        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        let isEnabled = try await MainActor.run {
            let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
            try yamlEngine.load()
            var config = yamlEngine.getConfig()
            config.rules["test_rule"] = RuleConfiguration(enabled: true)
            try yamlEngine.save(config: config, createBackup: false)
            
            // Verify it's enabled
            try yamlEngine.load()
            let updatedConfig = yamlEngine.getConfig()
            return updatedConfig.rules["test_rule"]?.enabled == true
        }
        #expect(isEnabled == true)
    }
    
    @Test("Workflow: batch simulation with progress tracking")
    func testBatchSimulationWithProgress() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        let workspace = Workspace(path: tempDir)
        let mockCLI = MockSwiftLintCLI()

        await mockCLI.setLintCommandHandler { _, _ in
            return try JSONSerialization.data(withJSONObject: [])
        }
        
        let simulator = await createImpactSimulator(swiftLintCLI: mockCLI)
        
        let ruleIds = ["rule1", "rule2", "rule3", "rule4", "rule5"]
        let (resultsCount, progressUpdates) = try await simulateBatchWithProgress(
            simulator: simulator,
            workspace: workspace,
            ruleIds: ruleIds
        )
        #expect(resultsCount == 5)
        #expect(progressUpdates.count == 5)
    }

    private func writeDisabledRulesConfig(in directory: URL) throws -> URL {
        let configPath = directory.appendingPathComponent(".swiftlint.yml")
        let config = """
        disabled_rules:
          - safe_rule_1
          - safe_rule_2
          - unsafe_rule
        """
        try config.write(to: configPath, atomically: true, encoding: .utf8)
        return configPath
    }

    private func configureMockCLIForSafeRuleDiscovery(_ mockCLI: MockSwiftLintCLI) async {
        actor CallCounter {
            var count = 0
            func increment() -> Int {
                count += 1
                return count
            }
        }
        let callCounter = CallCounter()

        await mockCLI.setLintCommandHandler { @Sendable _, _ in
            let currentCount = await callCounter.increment()
            if currentCount == 3 {
                let violation = [
                    "file": "Test.swift",
                    "line": 1,
                    "character": 1,
                    "severity": "warning",
                    "rule_id": "unsafe_rule",
                    "reason": "Test violation"
                ]
                return try JSONSerialization.data(withJSONObject: [violation])
            }
            return try JSONSerialization.data(withJSONObject: [])
        }
    }

    private struct RuleEnablement {
        let rule1Exists: Bool
        let rule1Enabled: Bool?
        let rule2Exists: Bool
        let rule2Enabled: Bool?
    }

    private func enableRules(_ ruleIds: [String], configPath: URL) async throws -> RuleEnablement {
        let updatedConfig = try await MainActor.run {
            let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
            try yamlEngine.load()
            var yamlConfig = yamlEngine.getConfig()

            for ruleId in ruleIds {
                if var ruleConfig = yamlConfig.rules[ruleId] {
                    ruleConfig.enabled = true
                    yamlConfig.rules[ruleId] = ruleConfig
                } else {
                    yamlConfig.rules[ruleId] = RuleConfiguration(enabled: true)
                }
            }

            try yamlEngine.save(config: yamlConfig, createBackup: false)
            try yamlEngine.load()
            return yamlEngine.getConfig()
        }

        return await MainActor.run {
            RuleEnablement(
                rule1Exists: updatedConfig.rules["safe_rule_1"] != nil,
                rule1Enabled: updatedConfig.rules["safe_rule_1"]?.enabled,
                rule2Exists: updatedConfig.rules["safe_rule_2"] != nil,
                rule2Enabled: updatedConfig.rules["safe_rule_2"]?.enabled
            )
        }
    }

    private func assertRuleEnablement(_ ruleEnablement: RuleEnablement) {
        if ruleEnablement.rule1Exists {
            #expect(ruleEnablement.rule1Enabled == true)
        }
        if ruleEnablement.rule2Exists {
            #expect(ruleEnablement.rule2Enabled == true)
        }
    }

    private struct ProgressUpdate {
        let current: Int
        let total: Int
        let ruleId: String
    }

    private actor ProgressCollector {
        var updates: [ProgressUpdate] = []
        func add(_ update: ProgressUpdate) {
            updates.append(update)
        }
    }

    private func simulateBatchWithProgress(
        simulator: ImpactSimulator,
        workspace: Workspace,
        ruleIds: [String]
    ) async throws -> (Int, [ProgressUpdate]) {
        let progressCollector = ProgressCollector()
        let batchResult = try await simulator.simulateRules(
            ruleIds: ruleIds,
            workspace: workspace,
            baseConfigPath: nil
        ) { @Sendable current, total, ruleId in
            Task {
                await progressCollector.add(ProgressUpdate(current: current, total: total, ruleId: ruleId))
            }
        }

        var progressUpdates: [ProgressUpdate] = []
        let didCollectAll = await UIAsyncTestHelpers.waitForConditionAsync(timeout: 1.0) {
            let updates = await progressCollector.updates
            progressUpdates = updates
            return updates.count == ruleIds.count
        }
        if !didCollectAll {
            progressUpdates = await progressCollector.updates
        }

        let resultsCount = batchResult.results.count
        return (resultsCount, progressUpdates)
    }
}
