//
//  ViolationStorageCountTests.swift
//  SwiftLIntRuleStudioTests
//
//  Count tests for ViolationStorageActor
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct ViolationStorageCountTests {
    @Test("ViolationStorageActor gets violation count")
    func testGetViolationCount() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let violations = [
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule1"),
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule2"),
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule3")
        ]

        try await storage.storeViolations(violations, for: workspaceId)

        let count = try await storage.getViolationCount(filter: .all, workspaceId: workspaceId)
        #expect(count == 3)

        let filter = ViolationFilter(ruleIDs: ["rule1"])
        let filteredCount = try await storage.getViolationCount(filter: filter, workspaceId: workspaceId)
        #expect(filteredCount == 1)
    }
}
