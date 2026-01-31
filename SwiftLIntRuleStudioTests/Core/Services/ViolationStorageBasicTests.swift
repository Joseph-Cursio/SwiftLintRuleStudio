//
//  ViolationStorageBasicTests.swift
//  SwiftLIntRuleStudioTests
//
//  Basic fetch and filter tests for ViolationStorage
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct ViolationStorageBasicTests {
    @Test("ViolationStorage stores violations")
    func testStoreViolations() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()
        let violations = [
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule1"),
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule2")
        ]

        try await storage.storeViolations(violations, for: workspaceId)

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        let (count, hasRule1, hasRule2) = await MainActor.run {
            (
                fetched.count,
                fetched.contains { $0.ruleID == "rule1" },
                fetched.contains { $0.ruleID == "rule2" }
            )
        }
        #expect(count == 2)
        #expect(hasRule1 == true)
        #expect(hasRule2 == true)
    }

    @Test("ViolationStorage fetches violations by workspace")
    func testFetchViolationsByWorkspace() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspace1 = UUID()
        let workspace2 = UUID()

        let violations1 = [ViolationStorageTestHelpers.createTestViolation(ruleID: "rule1")]
        let violations2 = [ViolationStorageTestHelpers.createTestViolation(ruleID: "rule2")]

        try await storage.storeViolations(violations1, for: workspace1)
        try await storage.storeViolations(violations2, for: workspace2)

        let fetched1 = try await storage.fetchViolations(filter: .all, workspaceId: workspace1)
        let fetched2 = try await storage.fetchViolations(filter: .all, workspaceId: workspace2)

        let (count1, ruleID1, count2, ruleID2) = await MainActor.run {
            (fetched1.count, fetched1.first?.ruleID, fetched2.count, fetched2.first?.ruleID)
        }
        #expect(count1 == 1)
        #expect(ruleID1 == "rule1")
        #expect(count2 == 1)
        #expect(ruleID2 == "rule2")
    }

    @Test("ViolationStorage filters violations by rule ID")
    func testFilterByRuleID() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let violations = [
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule1"),
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule2"),
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule3")
        ]

        try await storage.storeViolations(violations, for: workspaceId)

        let filter = await MainActor.run {
            var filter = ViolationFilter()
            filter.ruleIDs = ["rule1", "rule3"]
            return filter
        }

        let fetched = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)

        let (count, allMatch) = await MainActor.run {
            (fetched.count, fetched.allSatisfy { $0.ruleID == "rule1" || $0.ruleID == "rule3" })
        }
        #expect(count == 2)
        #expect(allMatch == true)
    }

    @Test("ViolationStorage filters violations by severity")
    func testFilterBySeverity() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let violations = [
            Violation(ruleID: "rule1", filePath: "Test.swift", line: 1, severity: .error, message: "Error"),
            Violation(ruleID: "rule2", filePath: "Test.swift", line: 2, severity: .warning, message: "Warning"),
            Violation(ruleID: "rule3", filePath: "Test.swift", line: 3, severity: .error, message: "Error")
        ]

        try await storage.storeViolations(violations, for: workspaceId)

        let filter = await MainActor.run {
            var filter = ViolationFilter()
            filter.severities = [.error]
            return filter
        }

        let fetched = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)

        let (count, allError) = await MainActor.run {
            (fetched.count, fetched.allSatisfy { $0.severity == .error })
        }
        #expect(count == 2)
        #expect(allError == true)
    }

    @Test("ViolationStorage filters violations by file path")
    func testFilterByFilePath() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let violations = [
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule1", filePath: "File1.swift"),
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule2", filePath: "File2.swift"),
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule3", filePath: "File1.swift")
        ]

        try await storage.storeViolations(violations, for: workspaceId)

        let filter = await MainActor.run {
            var filter = ViolationFilter()
            filter.filePaths = ["File1.swift"]
            return filter
        }

        let fetched = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)

        let (count, allMatch) = await MainActor.run {
            (fetched.count, fetched.allSatisfy { $0.filePath == "File1.swift" })
        }
        #expect(count == 2)
        #expect(allMatch == true)
    }

    @Test("ViolationStorage filters violations by suppressed status")
    func testFilterBySuppressed() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let violations = [
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule1"),
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule2")
        ]

        try await storage.storeViolations(violations, for: workspaceId)
        try await storage.suppressViolations([violations[0].id], reason: "Test reason")

        let filter1 = await MainActor.run {
            var filter = ViolationFilter()
            filter.suppressedOnly = true
            return filter
        }

        let suppressed = try await storage.fetchViolations(filter: filter1, workspaceId: workspaceId)
        let (suppressedCount, isSuppressed, suppressionReason) = await MainActor.run {
            (suppressed.count, suppressed.first?.suppressed, suppressed.first?.suppressionReason)
        }
        #expect(suppressedCount == 1)
        #expect(isSuppressed == true)
        #expect(suppressionReason == "Test reason")

        let filter2 = await MainActor.run {
            var filter = ViolationFilter()
            filter.suppressedOnly = false
            return filter
        }
        let notSuppressed = try await storage.fetchViolations(filter: filter2, workspaceId: workspaceId)
        let (notSuppressedCount, isNotSuppressed) = await MainActor.run {
            (notSuppressed.count, notSuppressed.first?.suppressed)
        }
        #expect(notSuppressedCount == 1)
        #expect(isNotSuppressed == false)
    }

    @Test("ViolationStorage handles date range filtering")
    func testFilterByDateRange() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let oldDate = Date().addingTimeInterval(-86400)
        let newDate = Date()

        let oldViolation = Violation(
            ruleID: "rule1",
            filePath: "Test.swift",
            line: 1,
            severity: .error,
            message: "Old",
            detectedAt: oldDate
        )

        let newViolation = Violation(
            ruleID: "rule2",
            filePath: "Test.swift",
            line: 2,
            severity: .error,
            message: "New",
            detectedAt: newDate
        )

        try await storage.storeViolations([oldViolation, newViolation], for: workspaceId)

        let yesterday = Date().addingTimeInterval(-43200)
        let filter = await MainActor.run {
            var filter = ViolationFilter()
            filter.dateRange = yesterday...Date()
            return filter
        }

        let fetched = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)
        let (count, ruleID) = await MainActor.run {
            (fetched.count, fetched.first?.ruleID)
        }
        #expect(count == 1)
        #expect(ruleID == "rule2")
    }

    @Test("ViolationStorage handles empty database")
    func testEmptyDatabase() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.isEmpty)

        let count = try await storage.getViolationCount(filter: .all, workspaceId: workspaceId)
        #expect(count == 0)
    }
}
