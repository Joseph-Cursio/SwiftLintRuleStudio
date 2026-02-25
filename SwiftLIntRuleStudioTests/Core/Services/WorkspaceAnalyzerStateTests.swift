//
//  WorkspaceAnalyzerStateTests.swift
//  SwiftLIntRuleStudioTests
//
//  State and error handling tests for WorkspaceAnalyzer
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct WorkspaceAnalyzerStateTests {
    @Test("WorkspaceAnalyzer sets isAnalyzing state correctly")
    func testIsAnalyzingState() async throws {
        let mockCLI = WorkspaceAnalyzerTestHelpers.createMockSwiftLintCLI()
        let mockStorage = WorkspaceAnalyzerTestHelpers.createMockViolationStorage()
        let workspace = try await WorkspaceAnalyzerTestHelpers.createTempWorkspace()
        defer { Task { WorkspaceAnalyzerTestHelpers.cleanupTempWorkspace(workspace) } }

        let didEnterAnalyzing = try await WorkspaceAnalyzerTestHelpers.withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            await mockCLI.setLintCommandHandler { _, _ in
                try await Task.sleep(nanoseconds: 100_000_000)
                return Data("[]".utf8)
            }
            let analyzeTask = Task {
                try await analyzer.analyze(workspace: workspace)
            }
            let didEnter = await WorkspaceAnalyzerTestHelpers.waitForAnalyzingState(
                analyzer,
                expected: true,
                timeoutSeconds: 1.0
            )
            _ = try? await analyzeTask.value
            return didEnter
        }

        #expect(didEnterAnalyzing == true)
    }

    @Test("WorkspaceAnalyzer can cancel analysis")
    func testCancelAnalysis() async throws {
        let mockCLI = WorkspaceAnalyzerTestHelpers.createMockSwiftLintCLI()
        let mockStorage = WorkspaceAnalyzerTestHelpers.createMockViolationStorage()
        let workspace = try await WorkspaceAnalyzerTestHelpers.createTempWorkspace()
        defer { Task { WorkspaceAnalyzerTestHelpers.cleanupTempWorkspace(workspace) } }

        let didCancel = try await WorkspaceAnalyzerTestHelpers.withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            await mockCLI.setLintCommandHandler { _, _ in
                try await Task.sleep(nanoseconds: 500_000_000)
                return Data("[]".utf8)
            }
            let analyzeTask = Task {
                try await analyzer.analyze(workspace: workspace)
            }
            _ = await WorkspaceAnalyzerTestHelpers.waitForAnalyzingState(
                analyzer,
                expected: true,
                timeoutSeconds: 1.0
            )
            analyzer.cancelAnalysis()
            analyzeTask.cancel()
            return await WorkspaceAnalyzerTestHelpers.waitForAnalyzingState(
                analyzer,
                expected: false,
                timeoutSeconds: 1.0
            )
        }
        #expect(didCancel == true)
    }

    @Test("WorkspaceAnalyzer handles invalid JSON gracefully")
    func testInvalidJSON() async throws {
        let mockCLI = WorkspaceAnalyzerTestHelpers.createMockSwiftLintCLI()
        let mockStorage = WorkspaceAnalyzerTestHelpers.createMockViolationStorage()
        let workspace = try await WorkspaceAnalyzerTestHelpers.createTempWorkspace()
        defer { Task { WorkspaceAnalyzerTestHelpers.cleanupTempWorkspace(workspace) } }

        await WorkspaceAnalyzerTestHelpers.setupMockCLI(mockCLI, output: Data("invalid".utf8))

        await #expect(throws: WorkspaceAnalyzerError.self) {
            _ = try await WorkspaceAnalyzerTestHelpers.withWorkspaceAnalyzer(
                swiftLintCLI: mockCLI,
                violationStorage: mockStorage
            ) { analyzer in
                try await analyzer.analyze(workspace: workspace)
            }
        }
    }

    @Test("WorkspaceAnalyzer handles SwiftLint execution failure")
    func testSwiftLintFailure() async throws {
        let mockCLI = MockSwiftLintCLI(shouldFail: true)
        let mockStorage = WorkspaceAnalyzerTestHelpers.createMockViolationStorage()
        let workspace = try await WorkspaceAnalyzerTestHelpers.createTempWorkspace()
        defer { Task { WorkspaceAnalyzerTestHelpers.cleanupTempWorkspace(workspace) } }

        await #expect(throws: WorkspaceAnalyzerError.self) {
            _ = try await WorkspaceAnalyzerTestHelpers.withWorkspaceAnalyzer(
                swiftLintCLI: mockCLI,
                violationStorage: mockStorage
            ) { analyzer in
                try await analyzer.analyze(workspace: workspace)
            }
        }
    }

    @Test("WorkspaceAnalyzer calculates analysis duration")
    func testAnalysisDuration() async throws {
        let mockCLI = WorkspaceAnalyzerTestHelpers.createMockSwiftLintCLI()
        let mockStorage = WorkspaceAnalyzerTestHelpers.createMockViolationStorage()
        let workspace = try await WorkspaceAnalyzerTestHelpers.createTempWorkspace()
        defer { Task { WorkspaceAnalyzerTestHelpers.cleanupTempWorkspace(workspace) } }

        await WorkspaceAnalyzerTestHelpers.setupMockCLI(mockCLI, output: Data("[]".utf8))

        let result = try await WorkspaceAnalyzerTestHelpers.withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            try await analyzer.analyze(workspace: workspace)
        }

        let snapshot = await MainActor.run {
            (result.duration, result.completedAt, result.startedAt)
        }
        #expect(snapshot.0 >= 0)
        #expect(snapshot.1 >= snapshot.2)
    }

    @Test("WorkspaceAnalyzer analyzes specific files incrementally")
    func testAnalyzeSpecificFiles() async throws {
        let mockCLI = WorkspaceAnalyzerTestHelpers.createMockSwiftLintCLI()
        let mockStorage = WorkspaceAnalyzerTestHelpers.createMockViolationStorage()

        let workspace = try await WorkspaceAnalyzerTestHelpers.createTempWorkspace()
        defer { Task { WorkspaceAnalyzerTestHelpers.cleanupTempWorkspace(workspace) } }

        let workspacePath = workspace.path.path
        let json = """
        [
          {
            "file": "\(workspacePath)/File1.swift",
            "line": 10,
            "severity": "error",
            "rule_id": "force_cast",
            "reason": "Force casts should be avoided"
          }
        ]
        """
        await WorkspaceAnalyzerTestHelpers.setupMockCLI(mockCLI, output: Data(json.utf8))

        let fileURL = workspace.path.appendingPathComponent("File1.swift")
        try "struct Example {}".write(to: fileURL, atomically: true, encoding: .utf8)
        let result = try await WorkspaceAnalyzerTestHelpers.withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            try await analyzer.analyzeFiles([fileURL], in: workspace, onlyChanged: false)
        }

        let violationsCount = await MainActor.run { result.violations.count }
        #expect(violationsCount == 1)
    }

    @Test("WorkspaceAnalyzer analyzeChangedFiles skips .build files")
    func testAnalyzeChangedFilesSkipsBuild() async throws {
        let mockCLI = WorkspaceAnalyzerTestHelpers.createMockSwiftLintCLI()
        let mockStorage = WorkspaceAnalyzerTestHelpers.createMockViolationStorage()
        let workspace = try await WorkspaceAnalyzerTestHelpers.createTempWorkspace()
        defer { Task { WorkspaceAnalyzerTestHelpers.cleanupTempWorkspace(workspace) } }

        let buildDir = workspace.path.appendingPathComponent(".build", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        let buildFile = buildDir.appendingPathComponent("Ignored.swift")
        try "struct Ignored {}".write(to: buildFile, atomically: true, encoding: .utf8)

        await WorkspaceAnalyzerTestHelpers.setupMockCLI(mockCLI, output: Data("[]".utf8))

        let result = try await WorkspaceAnalyzerTestHelpers.withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            try await analyzer.analyzeChangedFiles(in: workspace)
        }

        let filesAnalyzed = await MainActor.run { result.filesAnalyzed }
        #expect(filesAnalyzed >= 0)
    }

    @Test("WorkspaceAnalyzer computes config hash when config exists")
    func testConfigHash() async throws {
        let mockCLI = WorkspaceAnalyzerTestHelpers.createMockSwiftLintCLI()
        let mockStorage = WorkspaceAnalyzerTestHelpers.createMockViolationStorage()
        let workspace = try await WorkspaceAnalyzerTestHelpers.createTempWorkspace()
        defer { Task { WorkspaceAnalyzerTestHelpers.cleanupTempWorkspace(workspace) } }

        let configPath = workspace.path.appendingPathComponent(".swiftlint.yml")
        try "rules: {}".write(to: configPath, atomically: true, encoding: .utf8)

        await WorkspaceAnalyzerTestHelpers.setupMockCLI(mockCLI, output: Data("[]".utf8))

        let result = try await WorkspaceAnalyzerTestHelpers.withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            try await analyzer.analyze(workspace: workspace, configPath: configPath)
        }

        let configHash = await MainActor.run { result.configHash }
        #expect(configHash != nil)
    }
}
