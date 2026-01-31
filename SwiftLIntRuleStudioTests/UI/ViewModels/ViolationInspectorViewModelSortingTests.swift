import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct VIViewModelSortingTests {
    @Test("ViolationInspectorViewModel sorts by file")
    func testSortByFile() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(
                ruleID: "rule1",
                filePath: "FileB.swift",
                line: 10
            ),
            ViolationInspectorViewModelTestHelpers.createTestViolation(
                ruleID: "rule2",
                filePath: "FileA.swift",
                line: 5
            ),
            ViolationInspectorViewModelTestHelpers.createTestViolation(
                ruleID: "rule3",
                filePath: "FileC.swift",
                line: 15
            )
        ]

        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        await MainActor.run {
            viewModel.sortOption = .file
        }

        let (count, filePath0, filePath1, filePath2) = await MainActor.run {
            (
                viewModel.filteredViolations.count,
                viewModel.filteredViolations[0].filePath,
                viewModel.filteredViolations[1].filePath,
                viewModel.filteredViolations[2].filePath
            )
        }
        #expect(count == 3)
        #expect(filePath0 == "FileA.swift")
        #expect(filePath1 == "FileB.swift")
        #expect(filePath2 == "FileC.swift")
    }

    @Test("ViolationInspectorViewModel sorts by line number")
    func testSortByLine() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(
                ruleID: "rule1",
                filePath: "Test.swift",
                line: 30
            ),
            ViolationInspectorViewModelTestHelpers.createTestViolation(
                ruleID: "rule2",
                filePath: "Test.swift",
                line: 10
            ),
            ViolationInspectorViewModelTestHelpers.createTestViolation(
                ruleID: "rule3",
                filePath: "Test.swift",
                line: 20
            )
        ]

        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        await MainActor.run {
            viewModel.sortOption = .line
        }

        let (count, line0, line1, line2) = await MainActor.run {
            (
                viewModel.filteredViolations.count,
                viewModel.filteredViolations[0].line,
                viewModel.filteredViolations[1].line,
                viewModel.filteredViolations[2].line
            )
        }
        #expect(count == 3)
        #expect(line0 == 10)
        #expect(line1 == 20)
        #expect(line2 == 30)
    }

    @Test("ViolationInspectorViewModel sorts by severity")
    func testSortBySeverity() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1", severity: .warning),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2", severity: .error),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule3", severity: .warning)
        ]

        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        await MainActor.run {
            viewModel.sortOption = .severity
        }

        let (count, severity0) = await MainActor.run {
            (viewModel.filteredViolations.count, viewModel.filteredViolations[0].severity)
        }
        #expect(count == 3)
        #expect(severity0 == .error)
    }

    @Test("ViolationInspectorViewModel sorts by date")
    func testSortByDate() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let oldDate = Date().addingTimeInterval(-86400)
        let newDate = Date()

        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule1", detectedAt: oldDate),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule2", detectedAt: newDate),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "rule3", detectedAt: oldDate)
        ]

        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        await MainActor.run {
            viewModel.sortOption = .date
        }

        let (count, ruleID0) = await MainActor.run {
            (viewModel.filteredViolations.count, viewModel.filteredViolations[0].ruleID)
        }
        #expect(count == 3)
        #expect(ruleID0 == "rule2")
    }
}
