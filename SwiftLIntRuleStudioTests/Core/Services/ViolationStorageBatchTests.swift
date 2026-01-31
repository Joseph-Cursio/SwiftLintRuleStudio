//
//  ViolationStorageBatchTests.swift
//  SwiftLIntRuleStudioTests
//
//  Batch insert tests for ViolationStorage
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct ViolationStorageBatchTests {
    @Test("ViolationStorage handles large batch inserts")
    func testLargeBatchInsert() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let violations = (0..<100).map { index in
            ViolationStorageTestHelpers.createTestViolation(
                ruleID: "rule\(index)",
                filePath: "File\(index).swift"
            )
        }

        try await storage.storeViolations(violations, for: workspaceId)

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 100)
    }

    @Test("ViolationStorage handles very large batch inserts with transaction")
    func testVeryLargeBatchInsert() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let violations = (0..<1000).map { index in
            ViolationStorageTestHelpers.createTestViolation(
                ruleID: "rule\(index)",
                filePath: "File\(index % 10).swift"
            )
        }

        try await storage.storeViolations(violations, for: workspaceId)

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 1000)

        let count = try await storage.getViolationCount(filter: .all, workspaceId: workspaceId)
        #expect(count == 1000)

        let filter = await MainActor.run {
            var filter = ViolationFilter()
            filter.ruleIDs = ["rule0", "rule500", "rule999"]
            return filter
        }
        let filtered = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)
        #expect(filtered.count == 3)
    }
}
