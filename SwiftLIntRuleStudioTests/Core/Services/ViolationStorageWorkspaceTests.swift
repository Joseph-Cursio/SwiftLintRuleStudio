//
//  ViolationStorageWorkspaceTests.swift
//  SwiftLIntRuleStudioTests
//
//  Workspace-related tests for ViolationStorage
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct ViolationStorageWorkspaceTests {
    @Test("ViolationStorage deletes violations for workspace")
    func testDeleteViolations() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspace1 = UUID()
        let workspace2 = UUID()

        let violations1 = [ViolationStorageTestHelpers.createTestViolation(ruleID: "rule1")]
        let violations2 = [ViolationStorageTestHelpers.createTestViolation(ruleID: "rule2")]

        try await storage.storeViolations(violations1, for: workspace1)
        try await storage.storeViolations(violations2, for: workspace2)

        try await storage.deleteViolations(for: workspace1)

        let fetched1 = try await storage.fetchViolations(filter: .all, workspaceId: workspace1)
        let fetched2 = try await storage.fetchViolations(filter: .all, workspaceId: workspace2)

        #expect(fetched1.isEmpty)
        #expect(fetched2.count == 1)
    }

    @Test("ViolationStorage deletes old violations before storing new ones")
    func testStoreViolationsDeletesOldOnes() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let firstViolations = [
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule1"),
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule2"),
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule3")
        ]
        try await storage.storeViolations(firstViolations, for: workspaceId)

        let firstFetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(firstFetched.count == 3)

        let secondViolations = [
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule4"),
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule5")
        ]
        try await storage.storeViolations(secondViolations, for: workspaceId)

        let secondFetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(secondFetched.count == 2)
        #expect(secondFetched.allSatisfy { $0.ruleID == "rule4" || $0.ruleID == "rule5" } == true)
        #expect(secondFetched.contains { $0.ruleID == "rule4" } == true)
        #expect(secondFetched.contains { $0.ruleID == "rule5" } == true)
        #expect(secondFetched.contains { $0.ruleID == "rule1" } == false)
        #expect(secondFetched.contains { $0.ruleID == "rule2" } == false)
        #expect(secondFetched.contains { $0.ruleID == "rule3" } == false)
    }
}
