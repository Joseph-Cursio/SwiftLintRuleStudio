//
//  ViolationStorageBatchTests.swift
//  SwiftLintRuleStudioTests
//
//  Batch insert tests for ViolationStorageActor
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct ViolationStorageBatchTests {
    @Test("ViolationStorageActor handles large batch inserts")
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

    @Test("ViolationStorageActor handles very large batch inserts with transaction")
    func testVeryLargeBatchInsert() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let violations = (0..<1_000).map { index in
            ViolationStorageTestHelpers.createTestViolation(
                ruleID: "rule\(index)",
                filePath: "File\(index % 10).swift"
            )
        }

        try await storage.storeViolations(violations, for: workspaceId)

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 1_000)

        let count = try await storage.getViolationCount(filter: .all, workspaceId: workspaceId)
        #expect(count == 1_000)

        let filter = ViolationFilter(ruleIDs: ["rule0", "rule500", "rule999"])
        let filtered = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)
        #expect(filtered.count == 3)
    }
}
