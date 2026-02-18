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
        #expect(fetched.count == 2)
        #expect(fetched.contains { $0.ruleID == "rule1" } == true)
        #expect(fetched.contains { $0.ruleID == "rule2" } == true)
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

        #expect(fetched1.count == 1)
        #expect(fetched1.first?.ruleID == "rule1")
        #expect(fetched2.count == 1)
        #expect(fetched2.first?.ruleID == "rule2")
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

        let filter = ViolationFilter(ruleIDs: ["rule1", "rule3"])

        let fetched = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)

        #expect(fetched.count == 2)
        #expect(fetched.allSatisfy { $0.ruleID == "rule1" || $0.ruleID == "rule3" } == true)
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

        let filter = ViolationFilter(severities: [.error])

        let fetched = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)

        #expect(fetched.count == 2)
        #expect(fetched.allSatisfy { $0.severity == .error } == true)
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

        let filter = ViolationFilter(filePaths: ["File1.swift"])

        let fetched = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)

        #expect(fetched.count == 2)
        #expect(fetched.allSatisfy { $0.filePath == "File1.swift" } == true)
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

        let filter1 = ViolationFilter(suppressedOnly: true)

        let suppressed = try await storage.fetchViolations(filter: filter1, workspaceId: workspaceId)
        #expect(suppressed.count == 1)
        #expect(suppressed.first?.suppressed == true)
        #expect(suppressed.first?.suppressionReason == "Test reason")

        let filter2 = ViolationFilter(suppressedOnly: false)
        let notSuppressed = try await storage.fetchViolations(filter: filter2, workspaceId: workspaceId)
        #expect(notSuppressed.count == 1)
        #expect(notSuppressed.first?.suppressed == false)
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
        let filter = ViolationFilter(dateRange: yesterday...Date())

        let fetched = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)
        #expect(fetched.count == 1)
        #expect(fetched.first?.ruleID == "rule2")
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
