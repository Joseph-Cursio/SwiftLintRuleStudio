//
//  ViolationStorageCountTests.swift
//  SwiftLIntRuleStudioTests
//
//  Count tests for ViolationStorage
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct ViolationStorageCountTests {
    @Test("ViolationStorage gets violation count")
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

        let filter = await MainActor.run {
            var filter = ViolationFilter()
            filter.ruleIDs = ["rule1"]
            return filter
        }
        let filteredCount = try await storage.getViolationCount(filter: filter, workspaceId: workspaceId)
        #expect(filteredCount == 1)
    }
}
