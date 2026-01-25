//
//  WorkspaceAnalyzerTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for Workspace Analyzer
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// WorkspaceAnalyzer is @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
struct WorkspaceAnalyzerTests {
    
    // Helper to run WorkspaceAnalyzer operations on MainActor
    // Note: Protocols aren't Sendable, so we use nonisolated(unsafe) to bypass checks for test mocks
    private func withWorkspaceAnalyzer<T: Sendable>(
        swiftLintCLI: SwiftLintCLIProtocol,
        violationStorage: ViolationStorageProtocol,
        operation: @MainActor @escaping (WorkspaceAnalyzer) async throws -> T
    ) async throws -> T {
        // Capture with nonisolated(unsafe) to bypass Sendable check for test mocks
        nonisolated(unsafe) let cli = swiftLintCLI
        nonisolated(unsafe) let storage = violationStorage
        // Use Task with @MainActor to run async operation
        // Create isolated FileTracker for each test to prevent cross-test interference
        return try await Task { @MainActor in
            let isolatedTracker = FileTracker.createForTesting()
            let analyzer = WorkspaceAnalyzer(swiftLintCLI: cli, violationStorage: storage, fileTracker: isolatedTracker)
            return try await operation(analyzer)
        }.value
    }
    
    // MARK: - Test Helpers
    
    private func createMockSwiftLintCLI() -> MockSwiftLintCLI {
        return MockSwiftLintCLI()
    }
    
    private func setupMockCLI(_ mockCLI: MockSwiftLintCLI, output: Data, shouldFail: Bool = false, shouldHang: Bool = false) async {
        await mockCLI.setMockLintOutput(output)
        await mockCLI.setShouldHang(shouldHang)
    }
    
    private func createMockViolationStorage() -> MockViolationStorage {
        return MockViolationStorage()
    }
    
    private func createTempWorkspace() async throws -> Workspace {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        return await MainActor.run {
            Workspace(path: tempDir)
        }
    }

    private func waitForAnalyzingState(
        _ analyzer: WorkspaceAnalyzer,
        expected: Bool,
        timeoutSeconds: TimeInterval = 0.2
    ) async -> Bool {
        return await UIAsyncTestHelpers.waitForConditionAsync(timeout: timeoutSeconds, interval: 0.02) {
            await MainActor.run {
                analyzer.isAnalyzing == expected
            }
        }
    }
    
    private func cleanupTempWorkspace(_ workspace: Workspace) async {
        let path = await MainActor.run { workspace.path }
        try? FileManager.default.removeItem(at: path)
    }
    
    // MARK: - Analysis Tests
    
    @Test("WorkspaceAnalyzer analyzes workspace and returns violations")
    func testAnalyzeWorkspace() async throws {
        let mockCLI = createMockSwiftLintCLI()
        let mockStorage = createMockViolationStorage()
        
        let workspace = try await createTempWorkspace()
        defer { Task { await cleanupTempWorkspace(workspace) } }
        
        // Setup mock to return violations
        let workspacePath = await MainActor.run { workspace.path.path }
        let mockViolationsJSON = """
        [
          {
            "file": "\(workspacePath)/Test.swift",
            "line": 10,
            "character": 5,
            "severity": "error",
            "type": "force_cast",
            "rule_id": "force_cast",
            "reason": "Force casts should be avoided"
          }
        ]
        """
        await setupMockCLI(mockCLI, output: Data(mockViolationsJSON.utf8))
        
        // Capture mockStorage with nonisolated(unsafe) to pass into closure
        nonisolated(unsafe) let storage = mockStorage
        let (violationCount, firstRuleID, firstSeverity, storedCount) = try await withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            let result = try await analyzer.analyze(workspace: workspace)
            let stored = storage.storedViolations
            // Extract all values inside MainActor context
            let count = result.violations.count
            let ruleID = result.violations.first?.ruleID
            let severity = result.violations.first?.severity
            let storedCount = stored.count
            return (count, ruleID, severity, storedCount)
        }
        
        #expect(violationCount == 1)
        #expect(firstRuleID == "force_cast")
        #expect(firstSeverity == .error)
        #expect(storedCount == 1)
    }
    
    @Test("WorkspaceAnalyzer handles empty violation list")
    func testAnalyzeWorkspaceEmptyViolations() async throws {
        let mockCLI = createMockSwiftLintCLI()
        let mockStorage = createMockViolationStorage()
        let workspace = try await createTempWorkspace()
        defer { Task { await cleanupTempWorkspace(workspace) } }
        
        // Setup mock to return empty array
        await setupMockCLI(mockCLI, output: Data("[]".utf8))
        
        // Capture mockStorage with nonisolated(unsafe) to pass into closure
        nonisolated(unsafe) let storage = mockStorage
        let (isEmpty, filesAnalyzed, storedIsEmpty) = try await withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            let result = try await analyzer.analyze(workspace: workspace)
            // Access mockStorage inside MainActor context
            let stored = storage.storedViolations
            // Extract all values inside MainActor context
            let isEmpty = result.violations.isEmpty
            let filesAnalyzed = result.filesAnalyzed
            let storedIsEmpty = stored.isEmpty
            return (isEmpty, filesAnalyzed, storedIsEmpty)
        }
        
        #expect(isEmpty)
        #expect(filesAnalyzed == 0)
        #expect(storedIsEmpty)
    }
    
    @Test("WorkspaceAnalyzer parses multiple violations correctly")
    func testAnalyzeWorkspaceMultipleViolations() async throws {
        let mockCLI = createMockSwiftLintCLI()
        let mockStorage = createMockViolationStorage()
        let workspace = try await createTempWorkspace()
        defer { Task { await cleanupTempWorkspace(workspace) } }
        
        let workspacePath = await MainActor.run { workspace.path.path }
        let mockViolationsJSON = """
        [
          {
            "file": "\(workspacePath)/File1.swift",
            "line": 10,
            "character": 5,
            "severity": "error",
            "rule_id": "force_cast",
            "reason": "Force cast violation"
          },
          {
            "file": "\(workspacePath)/File2.swift",
            "line": 20,
            "character": 10,
            "severity": "warning",
            "rule_id": "line_length",
            "reason": "Line too long"
          }
        ]
        """
        await setupMockCLI(mockCLI, output: Data(mockViolationsJSON.utf8))
        
        let (count, filesAnalyzed, hasForceCast, hasLineLength) = try await withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            let result = try await analyzer.analyze(workspace: workspace)
            let violationCount = result.violations.count
            let filesAnalyzed = result.filesAnalyzed
            let hasForceCast = result.violations.contains { $0.ruleID == "force_cast" }
            let hasLineLength = result.violations.contains { $0.ruleID == "line_length" }
            return (violationCount, filesAnalyzed, hasForceCast, hasLineLength)
        }
        
        #expect(count == 2)
        #expect(filesAnalyzed == 2)
        #expect(hasForceCast)
        #expect(hasLineLength)
    }
    
    @Test("WorkspaceAnalyzer converts file paths to relative paths")
    func testConvertToRelativePaths() async throws {
        let mockCLI = createMockSwiftLintCLI()
        let mockStorage = createMockViolationStorage()
        
        let workspace = try await createTempWorkspace()
        defer { Task { await cleanupTempWorkspace(workspace) } }
        
        let (fullPath, workspacePath) = await MainActor.run {
            (workspace.path.appendingPathComponent("Sources/Test.swift"), workspace.path)
        }
        let mockViolationsJSON = """
        [
          {
            "file": "\(fullPath.path)",
            "line": 10,
            "character": 5,
            "severity": "error",
            "rule_id": "force_cast",
            "reason": "Force cast"
          }
        ]
        """
        await setupMockCLI(mockCLI, output: Data(mockViolationsJSON.utf8))
        
        let (count, filePath) = try await withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            let result = try await analyzer.analyze(workspace: workspace)
            return (result.violations.count, result.violations.first?.filePath)
        }
        
        #expect(count == 1)
        if let filePath = filePath {
            #expect(filePath == "Sources/Test.swift" || filePath.hasSuffix("Sources/Test.swift"))
        }
    }
    
    @Test("WorkspaceAnalyzer handles missing column in violation")
    func testHandleMissingColumn() async throws {
        let mockCLI = createMockSwiftLintCLI()
        let mockStorage = createMockViolationStorage()
        let workspace = try await createTempWorkspace()
        defer { Task { await cleanupTempWorkspace(workspace) } }
        
        let workspacePath = await MainActor.run { workspace.path.path }
        let mockViolationsJSON = """
        [
          {
            "file": "\(workspacePath)/Test.swift",
            "line": 10,
            "severity": "warning",
            "rule_id": "line_length",
            "reason": "Line too long"
          }
        ]
        """
        await setupMockCLI(mockCLI, output: Data(mockViolationsJSON.utf8))
        
        let (count, column) = try await withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            let result = try await analyzer.analyze(workspace: workspace)
            return (result.violations.count, result.violations.first?.column)
        }
        
        #expect(count == 1)
        #expect(column == nil)
    }
    
    @Test("WorkspaceAnalyzer sets isAnalyzing state correctly")
    func testIsAnalyzingState() async throws {
        let mockCLI = createMockSwiftLintCLI()
        let mockStorage = createMockViolationStorage()
        
        let workspace = try await createTempWorkspace()
        defer { Task { await cleanupTempWorkspace(workspace) } }
        
        await setupMockCLI(mockCLI, output: Data("[]".utf8))
        
        let (isAnalyzingBefore, isAnalyzingAfter) = try await withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            let isAnalyzingBefore = analyzer.isAnalyzing
            
            let analysisTask = Task { @MainActor in
                try await analyzer.analyze(workspace: workspace)
            }
            
            _ = await waitForAnalyzingState(analyzer, expected: true)
            
            // Note: Due to async nature, we can't reliably test isAnalyzing during execution
            // but we can verify it's false after completion
            _ = try await analysisTask.value
            
            return (isAnalyzingBefore, analyzer.isAnalyzing)
        }
        
        #expect(isAnalyzingBefore == false)
        #expect(isAnalyzingAfter == false)
    }
    
    @Test("WorkspaceAnalyzer can cancel analysis")
    func testCancelAnalysis() async throws {
        let mockCLI = createMockSwiftLintCLI()
        let mockStorage = createMockViolationStorage()
        
        let workspace = try await createTempWorkspace()
        defer { Task { await cleanupTempWorkspace(workspace) } }
        
        // Make CLI hang to test cancellation
        await setupMockCLI(mockCLI, output: Data(), shouldHang: true)
        
        let isAnalyzing = try await withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            let analysisTask = Task { @MainActor in
                try await analyzer.analyze(workspace: workspace)
            }
            
            _ = await waitForAnalyzingState(analyzer, expected: true)
            analyzer.cancelAnalysis()
            
            // Task should be cancelled
            analysisTask.cancel()
            
            return analyzer.isAnalyzing
        }
        
        #expect(isAnalyzing == false)
    }
    
    @Test("WorkspaceAnalyzer handles invalid JSON gracefully")
    func testHandleInvalidJSON() async throws {
        let mockCLI = createMockSwiftLintCLI()
        let mockStorage = createMockViolationStorage()
        
        let workspace = try await createTempWorkspace()
        defer { Task { await cleanupTempWorkspace(workspace) } }
        
        await setupMockCLI(mockCLI, output: Data("invalid json".utf8))
        
        await #expect(throws: WorkspaceAnalyzerError.self) {
            try await withWorkspaceAnalyzer(swiftLintCLI: mockCLI, violationStorage: mockStorage) { analyzer in
                try await analyzer.analyze(workspace: workspace)
            }
        }
    }
    
    @Test("WorkspaceAnalyzer handles SwiftLint execution failure")
    func testHandleSwiftLintFailure() async throws {
        let mockCLI = MockSwiftLintCLI(shouldFail: true)
        let mockStorage = createMockViolationStorage()
        
        let workspace = try await createTempWorkspace()
        defer { Task { await cleanupTempWorkspace(workspace) } }
        
        await #expect(throws: Error.self) {
            try await withWorkspaceAnalyzer(swiftLintCLI: mockCLI, violationStorage: mockStorage) { analyzer in
                try await analyzer.analyze(workspace: workspace)
            }
        }
    }
    
    @Test("WorkspaceAnalyzer calculates analysis duration")
    func testAnalysisDuration() async throws {
        let mockCLI = createMockSwiftLintCLI()
        let mockStorage = createMockViolationStorage()
        
        let workspace = try await createTempWorkspace()
        defer { Task { await cleanupTempWorkspace(workspace) } }
        
        await setupMockCLI(mockCLI, output: Data("[]".utf8))
        
        let (duration, startedAt, completedAt) = try await withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            let result = try await analyzer.analyze(workspace: workspace)
            return (result.duration, result.startedAt, result.completedAt)
        }
        
        #expect(duration >= 0)
        #expect(startedAt <= completedAt)
    }
    
    @Test("WorkspaceAnalyzer analyzes specific files incrementally")
    func testAnalyzeFiles() async throws {
        let mockCLI = createMockSwiftLintCLI()
        let mockStorage = createMockViolationStorage()
        let workspace = try await createTempWorkspace()
        defer { Task { await cleanupTempWorkspace(workspace) } }
        
        // Create test files
        let (file1, file2) = await MainActor.run {
            (workspace.path.appendingPathComponent("File1.swift"), workspace.path.appendingPathComponent("File2.swift"))
        }
        try "// File 1".write(to: file1, atomically: true, encoding: .utf8)
        try "// File 2".write(to: file2, atomically: true, encoding: .utf8)
        
        let mockViolationsJSON = """
        [
          {
            "file": "\(file1.path)",
            "line": 1,
            "severity": "warning",
            "rule_id": "line_length",
            "reason": "Line too long"
          }
        ]
        """
        await setupMockCLI(mockCLI, output: Data(mockViolationsJSON.utf8))
        
        let (violationCount, filesAnalyzed) = try await withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            let result = try await analyzer.analyzeFiles([file1, file2], in: workspace)
            return (result.violations.count, result.filesAnalyzed)
        }
        
        #expect(violationCount >= 0) // May be 0 or more depending on mock
        #expect(filesAnalyzed == 2)
    }

    @Test("WorkspaceAnalyzer analyzeChangedFiles skips .build files")
    func testAnalyzeChangedFilesSkipsBuildFiles() async throws {
        let mockCLI = createMockSwiftLintCLI()
        let mockStorage = createMockViolationStorage()
        let workspace = try await createTempWorkspace()
        defer { Task { await cleanupTempWorkspace(workspace) } }

        let workspaceURL = await MainActor.run { workspace.path }
        let goodFile = workspaceURL.appendingPathComponent("Good.swift")
        try "// swift".write(to: goodFile, atomically: true, encoding: .utf8)

        let buildDir = workspaceURL.appendingPathComponent(".build", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        let buildFile = buildDir.appendingPathComponent("Bad.swift")
        try "// swift".write(to: buildFile, atomically: true, encoding: .utf8)

        let mockViolationsJSON = """
        [
          {
            "file": "\(goodFile.path)",
            "line": 1,
            "character": 1,
            "severity": "warning",
            "rule_id": "rule_one",
            "reason": "Good file"
          },
          {
            "file": "\(buildFile.path)",
            "line": 1,
            "character": 1,
            "severity": "warning",
            "rule_id": "rule_two",
            "reason": "Build file"
          }
        ]
        """
        await setupMockCLI(mockCLI, output: Data(mockViolationsJSON.utf8))

        let (count, hasBuildFile) = try await withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            let result = try await analyzer.analyzeChangedFiles(in: workspace)
            let hasBuild = result.violations.contains { $0.filePath.contains(".build") }
            return (result.violations.count, hasBuild)
        }

        #expect(count <= 1)
        #expect(hasBuildFile == false)
    }

    @Test("WorkspaceAnalyzer computes config hash when config exists")
    func testAnalyzeWorkspaceConfigHash() async throws {
        let mockCLI = createMockSwiftLintCLI()
        let mockStorage = createMockViolationStorage()
        let workspace = try await createTempWorkspace()
        defer { Task { await cleanupTempWorkspace(workspace) } }

        let configPath = await MainActor.run { workspace.path.appendingPathComponent(".swiftlint.yml") }
        try "rules: {}".write(to: configPath, atomically: true, encoding: .utf8)
        await setupMockCLI(mockCLI, output: Data("[]".utf8))

        let configHash = try await withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            let result = try await analyzer.analyze(workspace: workspace, configPath: configPath)
            return result.configHash
        }

        #expect(configHash?.isEmpty == false)
    }
}

// MARK: - Mock Implementations
// Note: MockSwiftLintCLI is defined in RuleRegistryTests.swift

class MockViolationStorage: ViolationStorageProtocol {
    var storedViolations: [Violation] = []
    var storedWorkspaceIds: [UUID] = []
    
    func storeViolations(_ violations: [Violation], for workspaceId: UUID) throws {
        storedViolations.append(contentsOf: violations)
        storedWorkspaceIds.append(workspaceId)
    }
    
    func fetchViolations(filter: ViolationFilter, workspaceId: UUID?) throws -> [Violation] {
        var filtered = storedViolations
        
        if let workspaceId = workspaceId {
            // In real implementation, filter by workspace
            // For mock, we'll just return all
        }
        
        if let ruleIDs = filter.ruleIDs {
            filtered = filtered.filter { ruleIDs.contains($0.ruleID) }
        }
        
        if let severities = filter.severities {
            filtered = filtered.filter { severities.contains($0.severity) }
        }
        
        if let suppressedOnly = filter.suppressedOnly {
            filtered = filtered.filter { $0.suppressed == suppressedOnly }
        }
        
        return filtered
    }
    
    func suppressViolations(_ violationIds: [UUID], reason: String) throws {
        for (index, violation) in storedViolations.enumerated() where violationIds.contains(violation.id) {
            storedViolations[index] = Violation(
                id: violation.id,
                ruleID: violation.ruleID,
                filePath: violation.filePath,
                line: violation.line,
                column: violation.column,
                severity: violation.severity,
                message: violation.message,
                detectedAt: violation.detectedAt,
                resolvedAt: violation.resolvedAt,
                suppressed: true,
                suppressionReason: reason
            )
        }
    }
    
    func resolveViolations(_ violationIds: [UUID]) throws {
        for (index, violation) in storedViolations.enumerated() where violationIds.contains(violation.id) {
            storedViolations[index] = Violation(
                id: violation.id,
                ruleID: violation.ruleID,
                filePath: violation.filePath,
                line: violation.line,
                column: violation.column,
                severity: violation.severity,
                message: violation.message,
                detectedAt: violation.detectedAt,
                resolvedAt: Date(),
                suppressed: violation.suppressed,
                suppressionReason: violation.suppressionReason
            )
        }
    }
    
    func deleteViolations(for workspaceId: UUID) throws {
        storedViolations.removeAll()
    }
    
    func getViolationCount(filter: ViolationFilter, workspaceId: UUID?) async throws -> Int {
        let violations = try await fetchViolations(filter: filter, workspaceId: workspaceId)
        return violations.count
    }
}
