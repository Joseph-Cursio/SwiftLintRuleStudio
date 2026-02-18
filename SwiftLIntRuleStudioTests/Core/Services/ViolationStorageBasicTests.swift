//
//  ViolationStorageBasicTests.swift
//  SwiftLIntRuleStudioTests
//
//  Basic fetch and filter tests for ViolationStorage
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct StorageFilterCase: Sendable, CustomTestStringConvertible {
    let name: String
    let violations: [Violation]
    let filter: ViolationFilter
    let expectedCount: Int
    let predicate: @Sendable (Violation) -> Bool

    var testDescription: String { name }

    static let all: [StorageFilterCase] = [
        StorageFilterCase(
            name: "by rule ID",
            violations: [
                ViolationStorageTestHelpers.createTestViolation(ruleID: "rule1"),
                ViolationStorageTestHelpers.createTestViolation(ruleID: "rule2"),
                ViolationStorageTestHelpers.createTestViolation(ruleID: "rule3")
            ],
            filter: ViolationFilter(ruleIDs: ["rule1", "rule3"]),
            expectedCount: 2,
            predicate: { $0.ruleID == "rule1" || $0.ruleID == "rule3" }
        ),
        StorageFilterCase(
            name: "by severity",
            violations: [
                Violation(ruleID: "rule1", filePath: "Test.swift", line: 1, severity: .error, message: "Error"),
                Violation(ruleID: "rule2", filePath: "Test.swift", line: 2, severity: .warning, message: "Warning"),
                Violation(ruleID: "rule3", filePath: "Test.swift", line: 3, severity: .error, message: "Error")
            ],
            filter: ViolationFilter(severities: [.error]),
            expectedCount: 2,
            predicate: { $0.severity == .error }
        ),
        StorageFilterCase(
            name: "by file path",
            violations: [
                ViolationStorageTestHelpers.createTestViolation(ruleID: "rule1", filePath: "File1.swift"),
                ViolationStorageTestHelpers.createTestViolation(ruleID: "rule2", filePath: "File2.swift"),
                ViolationStorageTestHelpers.createTestViolation(ruleID: "rule3", filePath: "File1.swift")
            ],
            filter: ViolationFilter(filePaths: ["File1.swift"]),
            expectedCount: 2,
            predicate: { $0.filePath == "File1.swift" }
        )
    ]
}

@Suite("ViolationStorage", .tags(.storage))
struct ViolationStorageBasicTests {

    @Suite("Storing")
    struct Storing {
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
    }

    @Suite("Fetching")
    struct Fetching {
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
            let first1 = try #require(fetched1.first)
            #expect(first1.ruleID == "rule1")
            #expect(fetched2.count == 1)
            let first2 = try #require(fetched2.first)
            #expect(first2.ruleID == "rule2")
        }
    }

    @Suite("Filtering", .tags(.filtering))
    struct Filtering {
        @Test("ViolationStorage filters violations", arguments: StorageFilterCase.all)
        func testFilterViolations(_ filterCase: StorageFilterCase) async throws {
            let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
            let workspaceId = UUID()

            try await storage.storeViolations(filterCase.violations, for: workspaceId)

            let fetched = try await storage.fetchViolations(filter: filterCase.filter, workspaceId: workspaceId)

            #expect(fetched.count == filterCase.expectedCount)
            #expect(fetched.allSatisfy(filterCase.predicate))
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
            let suppressedViolation = try #require(suppressed.first)
            #expect(suppressedViolation.suppressed == true)
            #expect(suppressedViolation.suppressionReason == "Test reason")

            let filter2 = ViolationFilter(suppressedOnly: false)
            let notSuppressed = try await storage.fetchViolations(filter: filter2, workspaceId: workspaceId)
            #expect(notSuppressed.count == 1)
            let notSuppressedViolation = try #require(notSuppressed.first)
            #expect(notSuppressedViolation.suppressed == false)
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
            let fetchedViolation = try #require(fetched.first)
            #expect(fetchedViolation.ruleID == "rule2")
        }
    }

    @Suite("Edge Cases")
    struct EdgeCases {
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
}
