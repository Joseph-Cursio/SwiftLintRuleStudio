import Combine
import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport

@MainActor
final class MockWorkspaceAnalyzer: WorkspaceAnalyzerProtocol {
    var mockViolations: [Violation] = []
    var analyzeCallCount = 0
    var shouldFail = false
    var isAnalyzing = false
    var isAnalyzingPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    private let mockStorage: MockViolationStorageForViewModel

    init(mockStorage: MockViolationStorageForViewModel) {
        self.mockStorage = mockStorage
    }

    // swiftlint:disable:next async_without_await
    func analyze(workspace: Workspace, configPath _: URL?) async throws -> AnalysisResult {
        analyzeCallCount += 1

        if shouldFail {
            throw WorkspaceAnalyzerError.analysisFailed("Mock analysis failure")
        }

        try mockStorage.storeViolations(mockViolations, for: workspace.id)

        return AnalysisResult(
            violations: mockViolations,
            filesAnalyzed: Set(mockViolations.map(\.filePath)).count,
            duration: 0.1,
            startedAt: Date.now,
            completedAt: Date.now
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

    func fetchViolations(filter: ViolationFilter, workspaceId _: UUID?) throws -> [Violation] {
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
                ruleID: violation.ruleID,
                filePath: violation.filePath,
                line: violation.line,
                severity: violation.severity,
                message: violation.message,
                id: violation.id,
                column: violation.column,
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
                ruleID: violation.ruleID,
                filePath: violation.filePath,
                line: violation.line,
                severity: violation.severity,
                message: violation.message,
                id: violation.id,
                column: violation.column,
                detectedAt: violation.detectedAt,
                resolvedAt: Date.now,
                suppressed: violation.suppressed,
                suppressionReason: violation.suppressionReason
            )
        }
    }

    func deleteViolations(for _: UUID) throws {
        storedViolations.removeAll()
    }

    // swiftlint:disable:next async_without_await
    func getViolationCount(filter: ViolationFilter, workspaceId: UUID?) async throws -> Int {
        let violations = try fetchViolations(filter: filter, workspaceId: workspaceId)
        return violations.count
    }
}

enum ViolationInspectorViewModelTestHelpers {
    @MainActor
    static func createViolationInspectorViewModel(
        violationStorage: ViolationStorageProtocol,
        workspaceAnalyzer: (any WorkspaceAnalyzerProtocol)? = nil
    ) async -> ViolationInspectorViewModel {
        await MainActor.run {
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
        detectedAt: Date = Date.now,
        suppressed: Bool = false
    ) -> Violation {
        Violation(
            ruleID: ruleID,
            filePath: filePath,
            line: line,
            severity: severity,
            message: message,
            id: id,
            detectedAt: detectedAt,
            suppressed: suppressed
        )
    }
}
