import Foundation
@testable import SwiftLIntRuleStudio

enum ViolationInspectorViewModelTestHelpers {
    static func createViolationInspectorViewModel(
        violationStorage: ViolationStorageProtocol,
        workspaceAnalyzer: WorkspaceAnalyzer? = nil
    ) async -> ViolationInspectorViewModel {
        return await MainActor.run {
            ViolationInspectorViewModel(violationStorage: violationStorage, workspaceAnalyzer: workspaceAnalyzer)
        }
    }

    static func createMockViolationStorage() -> MockViolationStorageForViewModel {
        MockViolationStorageForViewModel()
    }

    static func createTestViolation(
        id: UUID = UUID(),
        ruleID: String = "test_rule",
        filePath: String = "Test.swift",
        line: Int = 10,
        severity: Severity = .warning,
        message: String = "Test violation",
        detectedAt: Date = Date(),
        suppressed: Bool = false
    ) -> Violation {
        Violation(
            id: id,
            ruleID: ruleID,
            filePath: filePath,
            line: line,
            severity: severity,
            message: message,
            detectedAt: detectedAt,
            suppressed: suppressed
        )
    }
}

@MainActor
class MockWorkspaceAnalyzer: WorkspaceAnalyzer {
    var mockViolations: [Violation] = []
    var analyzeCallCount = 0
    var shouldFail = false
    private let mockStorage: MockViolationStorageForViewModel

    init(mockStorage: MockViolationStorageForViewModel) {
        self.mockStorage = mockStorage
        let mockCLI = MockSwiftLintCLI()
        super.init(swiftLintCLI: mockCLI, violationStorage: mockStorage)
    }

    override func analyze(
        workspace: Workspace,
        configPath: URL? = nil
    ) async throws -> AnalysisResult {
        analyzeCallCount += 1

        if shouldFail {
            throw WorkspaceAnalyzerError.analysisFailed("Mock analysis failure")
        }

        try mockStorage.storeViolations(mockViolations, for: workspace.id)

        return AnalysisResult(
            violations: mockViolations,
            filesAnalyzed: Set(mockViolations.map { $0.filePath }).count,
            duration: 0.1,
            startedAt: Date(),
            completedAt: Date()
        )
    }
}

// @unchecked Sendable: Test mock with controlled single-threaded access in tests
class MockViolationStorageForViewModel: ViolationStorageProtocol, @unchecked Sendable {
    var storedViolations: [Violation] = []
    var storedWorkspaceIds: [UUID] = []

    func storeViolations(_ violations: [Violation], for workspaceId: UUID) throws {
        storedViolations.append(contentsOf: violations)
        storedWorkspaceIds.append(workspaceId)
    }

    func fetchViolations(filter: ViolationFilter, workspaceId: UUID?) throws -> [Violation] {
        var filtered = storedViolations

        if let ruleIDs = filter.ruleIDs {
            filtered = filtered.filter { ruleIDs.contains($0.ruleID) }
        }

        if let severities = filter.severities {
            filtered = filtered.filter { severities.contains($0.severity) }
        }

        if let suppressedOnly = filter.suppressedOnly {
            filtered = filtered.filter { $0.suppressed == suppressedOnly }
        }

        if let filePaths = filter.filePaths {
            filtered = filtered.filter { filePaths.contains($0.filePath) }
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
        let violations = try fetchViolations(filter: filter, workspaceId: workspaceId)
        return violations.count
    }
}
