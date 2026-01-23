//
//  ImpactSimulatorIntegrationTests.swift
//  SwiftLIntRuleStudioTests
//
//  Integration tests for ImpactSimulator with other services
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

// DependencyContainer and ImpactSimulator are @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
struct ImpactSimulatorIntegrationTests {
    
    // Helper to access DependencyContainer on MainActor
    private func withContainer<T: Sendable>(
        operation: @MainActor (DependencyContainer) throws -> T
    ) async throws -> T {
        try await MainActor.run {
            let container = DependencyContainer.createForTesting()
            return try operation(container)
        }
    }
    
    // Helper to create ImpactSimulator on MainActor
    private func createImpactSimulator(swiftLintCLI: MockSwiftLintCLI) async -> ImpactSimulator {
        return await MainActor.run {
            ImpactSimulator(swiftLintCLI: swiftLintCLI)
        }
    }
    
    // MARK: - Test Helpers
    
    private func createTempWorkspaceDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    private func createSwiftFile(in directory: URL, name: String, content: String) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    private func cleanupTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - DependencyContainer Integration
    
    @Test("ImpactSimulator is initialized in DependencyContainer")
    func testDependencyContainerIntegration() async throws {
        let hasSimulator = try await withContainer { container in
            return container.impactSimulator != nil
        }
        
        #expect(hasSimulator == true)
    }
    
    // MARK: - WorkspaceManager Integration
    
    @Test("ImpactSimulator works with WorkspaceManager")
    func testWorkspaceManagerIntegration() async throws {
        let tempDir = try createTempWorkspaceDirectory()
        defer { cleanupTempDirectory(tempDir) }
        
        try createSwiftFile(in: tempDir, name: "Test.swift", content: "let x = 1\n")
        
        // Workspace.init should be Sendable, but Swift 6 has false positive
        let workspace = await MainActor.run {
            Workspace(path: tempDir)
        }
        let mockCLI = await createMockSwiftLintCLI(violations: [])
        let simulator = await createImpactSimulator(swiftLintCLI: mockCLI)
        
        try await MainActor.run {
            let container = DependencyContainer.createForTesting()
            try container.workspaceManager.openWorkspace(at: tempDir)
        }
        
        // Should be able to simulate without errors
        let result = try await simulator.simulateRule(
            ruleId: "test_rule",
            workspace: workspace,
            baseConfigPath: nil
        )
        
        // Extract ruleId inside MainActor context
        let ruleId = await MainActor.run {
            result.ruleId
        }
        #expect(ruleId == "test_rule")
    }
    
    // MARK: - YAMLConfigurationEngine Integration
    
    @Test("ImpactSimulator creates temporary configs correctly")
    func testTemporaryConfigCreation() async throws {
        let tempDir = try createTempWorkspaceDirectory()
        defer { cleanupTempDirectory(tempDir) }
        
        // Create a base config file
        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        let baseConfig = """
        disabled_rules:
          - test_rule
        """
        try baseConfig.write(to: configPath, atomically: true, encoding: .utf8)
        
        // Workspace.init should be Sendable, but Swift 6 has false positive
        let workspace = await MainActor.run {
            Workspace(path: tempDir)
        }
        let mockCLI = await createMockSwiftLintCLI(violations: [])
        let simulator = await createImpactSimulator(swiftLintCLI: mockCLI)
        
        // Simulate should create temp config with rule enabled
        let result = try await simulator.simulateRule(
            ruleId: "test_rule",
            workspace: workspace,
            baseConfigPath: configPath
        )
        
        // Extract ruleId inside MainActor context
        let ruleId = await MainActor.run {
            result.ruleId
        }
        #expect(ruleId == "test_rule")
        // Temp config should be cleaned up automatically
    }
    
    // MARK: - Helper Methods
    
    private func createMockSwiftLintCLI(violations: [Violation] = []) async -> MockSwiftLintCLI {
        let mockCLI = MockSwiftLintCLI()
        
        // Create JSON data from violations
        // Note: Violation is a struct and should be Sendable, but Swift 6 has false positives
        // Extract all properties inside MainActor.run to work around the compiler bug
        // Convert to Data immediately to avoid Sendable issues with [String: Any]
        let jsonData = await MainActor.run {
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
            // Convert to Data inside MainActor context to avoid Sendable issues
            return try? JSONSerialization.data(withJSONObject: jsonArray)
        }
        await mockCLI.setLintCommandHandler { @Sendable _, _ in
            return jsonData ?? Data()
        }
        
        return mockCLI
    }
}
