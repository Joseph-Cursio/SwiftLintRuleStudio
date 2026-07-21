import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct ViolationInspectorViewModelSortingTests {
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

        let sorted = await MainActor.run { viewModel.filteredViolations }
        try #require(sorted.count == 3, "Expected 3 sorted violations")
        #expect(sorted[0].filePath == "FileA.swift")
        #expect(sorted[1].filePath == "FileB.swift")
        #expect(sorted[2].filePath == "FileC.swift")
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

        let sorted = await MainActor.run { viewModel.filteredViolations }
        try #require(sorted.count == 3, "Expected 3 sorted violations")
        #expect(sorted[0].line == 10)
        #expect(sorted[1].line == 20)
        #expect(sorted[2].line == 30)
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

        let sorted = await MainActor.run { viewModel.filteredViolations }
        try #require(sorted.count == 3, "Expected 3 sorted violations")
        #expect(sorted[0].severity == .error)
    }

    @Test("ViolationInspectorViewModel sorts by date")
    func testSortByDate() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )

        let workspaceId = UUID()
        let oldDate = Date.now.addingTimeInterval(-86_400)
        let newDate = Date.now

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

        let sorted = await MainActor.run { viewModel.filteredViolations }
        try #require(sorted.count == 3, "Expected 3 sorted violations")
        #expect(sorted[0].ruleID == "rule2")
    }

    // MARK: - Descending direction (P1.1 regression)
    //
    // The .severity/.date/.line cases previously returned from inside the switch
    // and never consulted sortOrder, so toggling to .descending did nothing. These
    // pin the reversed order; ascending is already covered by the tests above.

    @Test("Severity sort honors descending (warning before error)")
    func testSortBySeverityDescending() async throws {
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
            viewModel.sortOrder = .descending
        }

        let sorted = await MainActor.run { viewModel.filteredViolations }
        try #require(sorted.count == 3)
        #expect(sorted[0].severity == .warning, "descending must put warnings before errors")
        #expect(sorted[2].severity == .error)
    }

    @Test("Date sort honors descending (oldest before newest)")
    func testSortByDateDescending() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )
        let workspaceId = UUID()
        let oldDate = Date.now.addingTimeInterval(-86_400)
        let newDate = Date.now
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "old", detectedAt: oldDate),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "new", detectedAt: newDate)
        ]
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        await MainActor.run {
            viewModel.sortOption = .date
            viewModel.sortOrder = .descending
        }

        let sorted = await MainActor.run { viewModel.filteredViolations }
        try #require(sorted.count == 2)
        // Ascending shows newest first (see testSortByDate); descending must reverse it.
        #expect(sorted[0].ruleID == "old")
        #expect(sorted[1].ruleID == "new")
    }

    @Test("Line sort honors descending (higher line first)")
    func testSortByLineDescending() async throws {
        let mockStorage = ViolationInspectorViewModelTestHelpers.createMockViolationStorage()
        let viewModel = await ViolationInspectorViewModelTestHelpers.createViolationInspectorViewModel(
            violationStorage: mockStorage
        )
        let workspaceId = UUID()
        let violations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(
                ruleID: "rule1", filePath: "Test.swift", line: 30
            ),
            ViolationInspectorViewModelTestHelpers.createTestViolation(
                ruleID: "rule2", filePath: "Test.swift", line: 10
            ),
            ViolationInspectorViewModelTestHelpers.createTestViolation(
                ruleID: "rule3", filePath: "Test.swift", line: 20
            )
        ]
        try await mockStorage.storeViolations(violations, for: workspaceId)
        try await viewModel.loadViolations(for: workspaceId)

        await MainActor.run {
            viewModel.sortOption = .line
            viewModel.sortOrder = .descending
        }

        let sorted = await MainActor.run { viewModel.filteredViolations }
        try #require(sorted.count == 3)
        #expect(sorted[0].line == 30)
        #expect(sorted[1].line == 20)
        #expect(sorted[2].line == 10)
    }
}
