//
//  ImpactSimulatorTests.swift
//  SwiftLIntRuleStudioTests
//
//  Unit tests for ImpactSimulator
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

// ImpactSimulator is @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
struct ImpactSimulatorTests {
    
    // MARK: - Test Helpers
    
    // Helper to run ImpactSimulator operations on MainActor
    private func withImpactSimulator<T: Sendable>(
        swiftLintCLI: SwiftLintCLIProtocol,
        operation: @MainActor @escaping (ImpactSimulator) async throws -> T
    ) async throws -> T {
        // Capture swiftLintCLI with nonisolated(unsafe) since it's a protocol that should be Sendable
        nonisolated(unsafe) let cliCapture = swiftLintCLI
        return try await Task { @MainActor in
            let simulator = ImpactSimulator(swiftLintCLI: cliCapture)
            return try await operation(simulator)
        }.value
    }
    
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
        
        // Set up handler to return violations
        await mockCLI.setLintCommandHandler { @Sendable _, _ in
            return jsonData ?? Data()
        }
        
        return mockCLI
    }
    
    // MARK: - Single Rule Simulation Tests
    
    @Test("ImpactSimulator simulates rule with zero violations")
    func testSimulateRuleZeroViolations() async throws {
        let tempDir = try createTempWorkspaceDirectory()
        defer { cleanupTempDirectory(tempDir) }
        
        // Create a Swift file
        _ = try createSwiftFile(in: tempDir, name: "Test.swift", content: "let x = 1\n")
        
        // Workspace.init should be Sendable, but Swift 6 has false positive
        let workspace = await MainActor.run {
            Workspace(path: tempDir)
        }
        let mockCLI = await createMockSwiftLintCLI(violations: [])
        
        let result = try await withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "test_rule",
                workspace: workspace,
                baseConfigPath: nil
            )
        }
        
        // Extract properties inside MainActor context
        let (ruleId, violationCount, isSafe, hasViolations, affectedFiles) = await MainActor.run {
            return (result.ruleId, result.violationCount, result.isSafe, result.hasViolations, result.affectedFiles)
        }
        
        #expect(ruleId == "test_rule")
        #expect(violationCount == 0)
        #expect(isSafe == true)
        #expect(hasViolations == false)
        #expect(affectedFiles.isEmpty)
    }
    
    @Test("ImpactSimulator simulates rule with violations")
    func testSimulateRuleWithViolations() async throws {
        let tempDir = try createTempWorkspaceDirectory()
        defer { cleanupTempDirectory(tempDir) }
        
        // Create a Swift file
        _ = try createSwiftFile(in: tempDir, name: "Test.swift", content: "let x = 1\n")
        
        let violations = [
            Violation(
                ruleID: "test_rule",
                filePath: "Test.swift",
                line: 1,
                column: 1,
                severity: .warning,
                message: "Test violation"
            )
        ]
        
        // Workspace.init should be Sendable, but Swift 6 has false positive
        let workspace = await MainActor.run {
            Workspace(path: tempDir)
        }
        let mockCLI = await createMockSwiftLintCLI(violations: violations)
        
        let result = try await withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "test_rule",
                workspace: workspace,
                baseConfigPath: nil
            )
        }
        
        // Extract properties inside MainActor context
        let (ruleId, violationCount, isSafe, hasViolations, affectedFiles) = await MainActor.run {
            return (result.ruleId, result.violationCount, result.isSafe, result.hasViolations, result.affectedFiles)
        }
        
        #expect(ruleId == "test_rule")
        #expect(violationCount == 1)
        #expect(isSafe == false)
        #expect(hasViolations == true)
        #expect(affectedFiles.count == 1)
        #expect(affectedFiles.contains("Test.swift"))
    }
    
    @Test("ImpactSimulator filters violations by rule ID")
    func testSimulateRuleFiltersByRuleId() async throws {
        let tempDir = try createTempWorkspaceDirectory()
        defer { cleanupTempDirectory(tempDir) }
        
        let violations = [
            Violation(
                ruleID: "test_rule",
                filePath: "Test.swift",
                line: 1,
                severity: .warning,
                message: "Test violation"
            ),
            Violation(
                ruleID: "other_rule",
                filePath: "Test.swift",
                line: 2,
                severity: .error,
                message: "Other violation"
            )
        ]
        
        // Workspace.init should be Sendable, but Swift 6 has false positive
        let workspace = await MainActor.run {
            Workspace(path: tempDir)
        }
        let mockCLI = await createMockSwiftLintCLI(violations: violations)
        
        let result = try await withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "test_rule",
                workspace: workspace,
                baseConfigPath: nil
            )
        }
        
        // Should only count violations for test_rule - extract inside MainActor context
        let (violationCount, violationsCount) = await MainActor.run {
            (result.violationCount, result.violations.count)
        }
        #expect(violationCount == 1)
        #expect(violationsCount == 1)
        // Extract ruleID inside MainActor context
        let ruleID = await MainActor.run {
            result.violations.first?.ruleID
        }
        #expect(ruleID == "test_rule")
    }
    
    // MARK: - Batch Simulation Tests
    
    @Test("ImpactSimulator simulates multiple rules")
    func testSimulateMultipleRules() async throws {
        let tempDir = try createTempWorkspaceDirectory()
        defer { cleanupTempDirectory(tempDir) }
        
        // Workspace.init should be Sendable, but Swift 6 has false positive
        let workspace = await MainActor.run {
            Workspace(path: tempDir)
        }
        let mockCLI = MockSwiftLintCLI()
        
        // Use actor for thread-safe call counting
        actor CallCounter {
            var count = 0
            func increment() -> Int {
                count += 1
                return count
            }
            func getCount() -> Int {
                return count
            }
        }
        let callCounter = CallCounter()
        
        // Set up mock to return different results based on rule
        await mockCLI.setLintCommandHandler { @Sendable _, _ in
            _ = await callCounter.increment()
            // Return empty violations for all rules
            return try JSONSerialization.data(withJSONObject: [])
        }
        
        let ruleIds = ["rule1", "rule2", "rule3"]
        let result = try await withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRules(
                ruleIds: ruleIds,
                workspace: workspace,
                baseConfigPath: nil
            )
        }
        
        // Extract properties inside MainActor context
        let (resultsCount, safeRulesCount, rulesWithViolationsCount) = await MainActor.run {
            return (result.results.count, result.safeRules.count, result.rulesWithViolations.count)
        }
        
        #expect(resultsCount == 3)
        #expect(await callCounter.getCount() == 3)
        #expect(safeRulesCount == 3)
        #expect(rulesWithViolationsCount == 0)
    }
    
    @Test("ImpactSimulator tracks progress during batch simulation")
    func testBatchSimulationProgress() async throws {
        let tempDir = try createTempWorkspaceDirectory()
        defer { cleanupTempDirectory(tempDir) }
        
        // Workspace.init should be Sendable, but Swift 6 has false positive
        let workspace = await MainActor.run {
            Workspace(path: tempDir)
        }
        let mockCLI = MockSwiftLintCLI()
        await mockCLI.setLintCommandHandler { _, _ in
            return try JSONSerialization.data(withJSONObject: [])
        }
        
        // Use an actor to safely collect progress updates
        struct ProgressUpdate {
            let current: Int
            let total: Int
            let ruleId: String
        }

        actor ProgressCollector {
            var updates: [ProgressUpdate] = []
            func add(_ update: ProgressUpdate) {
                updates.append(update)
            }
        }
        
        let progressCollector = ProgressCollector()
        let ruleIds = ["rule1", "rule2", "rule3"]
        _ = try await withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRules(
                ruleIds: ruleIds,
                workspace: workspace,
                baseConfigPath: nil
            ) { @Sendable current, total, ruleId in
                Task {
                    await progressCollector.add(ProgressUpdate(current: current, total: total, ruleId: ruleId))
                }
            }
        }
        
        // Wait a moment for all progress updates to be collected
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        let progressUpdates = await progressCollector.updates
        
        #expect(progressUpdates.count == 3)
        #expect(progressUpdates[0].current == 0)
        #expect(progressUpdates[0].total == 3)
        #expect(progressUpdates[0].ruleId == "rule1")
        #expect(progressUpdates[1].current == 1)
        #expect(progressUpdates[1].ruleId == "rule2")
        #expect(progressUpdates[2].current == 2)
        #expect(progressUpdates[2].ruleId == "rule3")
    }
    
    // MARK: - Safe Rule Detection Tests
    
    @Test("ImpactSimulator finds safe rules with zero violations")
    func testFindSafeRules() async throws {
        let tempDir = try createTempWorkspaceDirectory()
        defer { cleanupTempDirectory(tempDir) }
        
        // Workspace.init should be Sendable, but Swift 6 has false positive
        let workspace = await MainActor.run {
            Workspace(path: tempDir)
        }
        let mockCLI = MockSwiftLintCLI()
        
        // Return empty violations for all rules
        await mockCLI.setLintCommandHandler { _, _ in
            return try JSONSerialization.data(withJSONObject: [])
        }
        
        let disabledRuleIds = ["rule1", "rule2", "rule3"]
        let safeRules = try await withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.findSafeRules(
                workspace: workspace,
                baseConfigPath: nil,
                disabledRuleIds: disabledRuleIds
            )
        }
        
        #expect(safeRules.count == 3)
        #expect(safeRules.contains("rule1"))
        #expect(safeRules.contains("rule2"))
        #expect(safeRules.contains("rule3"))
    }
    
    @Test("ImpactSimulator filters out rules with violations from safe rules")
    func testFindSafeRulesFiltersViolations() async throws {
        let tempDir = try createTempWorkspaceDirectory()
        defer { cleanupTempDirectory(tempDir) }
        
        // Workspace.init should be Sendable, but Swift 6 has false positive
        let workspace = await MainActor.run {
            Workspace(path: tempDir)
        }
        let mockCLI = MockSwiftLintCLI()
        
        // Use actor for thread-safe call counting
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
            // Return violations for rule2, none for others
            if currentCount == 2 {
                let violation = [
                    "file": "Test.swift",
                    "line": 1,
                    "character": 1,
                    "severity": "warning",
                    "rule_id": "rule2",
                    "reason": "Test violation"
                ]
                return try JSONSerialization.data(withJSONObject: [violation])
            }
            return try JSONSerialization.data(withJSONObject: [])
        }
        
        let disabledRuleIds = ["rule1", "rule2", "rule3"]
        let safeRules = try await withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.findSafeRules(
                workspace: workspace,
                baseConfigPath: nil,
                disabledRuleIds: disabledRuleIds
            )
        }
        
        #expect(safeRules.count == 2)
        #expect(safeRules.contains("rule1"))
        #expect(safeRules.contains("rule3"))
        #expect(!safeRules.contains("rule2"))
    }
    
    // MARK: - Error Handling Tests
    
    @Test("ImpactSimulator handles simulation errors gracefully")
    func testSimulationErrorHandling() async throws {
        let tempDir = try createTempWorkspaceDirectory()
        defer { cleanupTempDirectory(tempDir) }
        
        // Workspace.init should be Sendable, but Swift 6 has false positive
        let workspace = await MainActor.run {
            Workspace(path: tempDir)
        }
        let mockCLI = MockSwiftLintCLI()
        
        // Make lint command throw an error
        await mockCLI.setLintCommandHandler { _, _ in
            throw SwiftLintError.executionFailed(message: "Test error")
        }
        
        // Should throw error for single rule
        do {
            _ = try await withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
                try await simulator.simulateRule(
                    ruleId: "test_rule",
                    workspace: workspace,
                    baseConfigPath: nil
                )
            }
            Issue.record("Expected error to be thrown")
        } catch {
            // Expected
        }
    }
    
    @Test("ImpactSimulator handles errors in batch simulation")
    func testBatchSimulationErrorHandling() async throws {
        let tempDir = try createTempWorkspaceDirectory()
        defer { cleanupTempDirectory(tempDir) }
        
        // Workspace.init should be Sendable, but Swift 6 has false positive
        let workspace = await MainActor.run {
            Workspace(path: tempDir)
        }
        let mockCLI = MockSwiftLintCLI()
        
        // Use actor for thread-safe call counting
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
            // Error on second call, success on others
            if currentCount == 2 {
                throw SwiftLintError.executionFailed(message: "Test error")
            }
            return try JSONSerialization.data(withJSONObject: [])
        }
        
        let ruleIds = ["rule1", "rule2", "rule3"]
        let result = try await withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRules(
                ruleIds: ruleIds,
                workspace: workspace,
                baseConfigPath: nil
            )
        }
        
        // Should have 3 results, but rule2 should have error indicator
        // Extract properties inside MainActor context
        let (resultsCount, violationCount0, violationCount1, violationCount2) = await MainActor.run {
            return (result.results.count, result.results[0].violationCount, result.results[1].violationCount, result.results[2].violationCount)
        }
        #expect(resultsCount == 3)
        #expect(violationCount0 == 0)
        #expect(violationCount1 == -1) // Error indicator
        #expect(violationCount2 == 0)
    }
}

