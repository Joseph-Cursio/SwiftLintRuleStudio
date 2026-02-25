//
//  WorkspaceAnalyzerAnalysisTests.swift
//  SwiftLIntRuleStudioTests
//
//  Analysis and parsing tests for WorkspaceAnalyzer
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct WorkspaceAnalyzerAnalysisTests {
    @Test("WorkspaceAnalyzer analyzes workspace and returns violations")
    func testAnalyzeWorkspace() async throws {
        let mockCLI = WorkspaceAnalyzerTestHelpers.createMockSwiftLintCLI()
        let mockStorage = WorkspaceAnalyzerTestHelpers.createMockViolationStorage()

        let workspace = try await WorkspaceAnalyzerTestHelpers.createTempWorkspace()
        defer { Task { WorkspaceAnalyzerTestHelpers.cleanupTempWorkspace(workspace) } }

        let workspacePath = workspace.path.path
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
        await WorkspaceAnalyzerTestHelpers.setupMockCLI(mockCLI, output: Data(mockViolationsJSON.utf8))

        let (violationCount, firstRuleID, firstSeverity, storedCount) = try await WorkspaceAnalyzerTestHelpers
            .withWorkspaceAnalyzer(
                swiftLintCLI: mockCLI,
                violationStorage: mockStorage
            ) { analyzer in
                let result = try await analyzer.analyze(workspace: workspace)
                let stored = mockStorage.storedViolations
                return await MainActor.run {
                    (
                        result.violations.count,
                        result.violations.first?.ruleID,
                        result.violations.first?.severity,
                        stored.count
                    )
                }
            }

        #expect(violationCount == 1)
        #expect(firstRuleID == "force_cast")
        #expect(firstSeverity == .error)
        #expect(storedCount == 1)
    }

    @Test("WorkspaceAnalyzer handles empty violation list")
    func testAnalyzeEmptyViolations() async throws {
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
            (result.violations.isEmpty, result.filesAnalyzed)
        }
        #expect(snapshot.0)
        #expect(snapshot.1 == 0)
    }

    @Test("WorkspaceAnalyzer parses multiple violations correctly")
    func testParseMultipleViolations() async throws {
        let mockCLI = WorkspaceAnalyzerTestHelpers.createMockSwiftLintCLI()
        let mockStorage = WorkspaceAnalyzerTestHelpers.createMockViolationStorage()

        let workspace = try await WorkspaceAnalyzerTestHelpers.createTempWorkspace()
        defer { Task { WorkspaceAnalyzerTestHelpers.cleanupTempWorkspace(workspace) } }

        let workspacePath = workspace.path.path
        let mockViolationsJSON = """
        [
          {
            "file": "\(workspacePath)/File1.swift",
            "line": 10,
            "character": 5,
            "severity": "error",
            "rule_id": "force_cast",
            "reason": "Force casts should be avoided"
          },
          {
            "file": "\(workspacePath)/File2.swift",
            "line": 20,
            "character": 3,
            "severity": "warning",
            "rule_id": "line_length",
            "reason": "Line is too long"
          }
        ]
        """
        await WorkspaceAnalyzerTestHelpers.setupMockCLI(mockCLI, output: Data(mockViolationsJSON.utf8))

        let result = try await WorkspaceAnalyzerTestHelpers.withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            try await analyzer.analyze(workspace: workspace)
        }

        let parsed = await MainActor.run {
            (result.violations.count, result.violations.first?.ruleID, result.violations.dropFirst().first?.ruleID)
        }
        #expect(parsed.0 == 2)
        #expect(parsed.1 == "force_cast")
        #expect(parsed.2 == "line_length")
    }

    @Test("WorkspaceAnalyzer converts file paths to relative paths")
    func testRelativePathConversion() async throws {
        let mockCLI = WorkspaceAnalyzerTestHelpers.createMockSwiftLintCLI()
        let mockStorage = WorkspaceAnalyzerTestHelpers.createMockViolationStorage()

        let workspace = try await WorkspaceAnalyzerTestHelpers.createTempWorkspace()
        defer { Task { WorkspaceAnalyzerTestHelpers.cleanupTempWorkspace(workspace) } }

        let workspacePath = workspace.path.path
        let mockViolationsJSON = """
        [
          {
            "file": "\(workspacePath)/Sources/Test.swift",
            "line": 10,
            "character": 5,
            "severity": "error",
            "rule_id": "force_cast",
            "reason": "Force casts should be avoided"
          }
        ]
        """
        await WorkspaceAnalyzerTestHelpers.setupMockCLI(mockCLI, output: Data(mockViolationsJSON.utf8))

        let result = try await WorkspaceAnalyzerTestHelpers.withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            try await analyzer.analyze(workspace: workspace)
        }

        let filePath = await MainActor.run {
            result.violations.first?.filePath
        }
        #expect(filePath == "Sources/Test.swift")
    }

    @Test("WorkspaceAnalyzer handles missing column in violation")
    func testMissingColumn() async throws {
        let mockCLI = WorkspaceAnalyzerTestHelpers.createMockSwiftLintCLI()
        let mockStorage = WorkspaceAnalyzerTestHelpers.createMockViolationStorage()

        let workspace = try await WorkspaceAnalyzerTestHelpers.createTempWorkspace()
        defer { Task { WorkspaceAnalyzerTestHelpers.cleanupTempWorkspace(workspace) } }

        let workspacePath = workspace.path.path
        let mockViolationsJSON = """
        [
          {
            "file": "\(workspacePath)/Test.swift",
            "line": 10,
            "severity": "error",
            "rule_id": "force_cast",
            "reason": "Force casts should be avoided"
          }
        ]
        """
        await WorkspaceAnalyzerTestHelpers.setupMockCLI(mockCLI, output: Data(mockViolationsJSON.utf8))

        let result = try await WorkspaceAnalyzerTestHelpers.withWorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: mockStorage
        ) { analyzer in
            try await analyzer.analyze(workspace: workspace)
        }

        let column = await MainActor.run {
            result.violations.first?.column
        }
        #expect(column == nil)
    }
}
