//
//  ViolationStorageTransactionTests.swift
//  SwiftLintRuleStudioTests
//
//  A failed store rolls back for ViolationStorageActor
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct ViolationStorageTransactionTests {
    @Test("ViolationStorageActor keeps the previous violations when a store fails partway")
    func testFailedStoreRollsBack() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()
        let original = [
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule1"),
            ViolationStorageTestHelpers.createTestViolation(ruleID: "rule2"),
        ]
        try await storage.storeViolations(original, for: workspaceId)

        // The store deletes the old rows and inserts `replacement` before the refused row fails.
        try await storage.executeSQL("""
        CREATE TRIGGER refuse_insert BEFORE INSERT ON violations WHEN NEW.rule_id = 'refused'
        BEGIN SELECT RAISE(ABORT, 'refused'); END;
        """)
        let replacement = ViolationStorageTestHelpers.createTestViolation(ruleID: "rule3")
        await #expect(throws: ViolationStorageError.self) {
            try await storage.storeViolations(
                [replacement, ViolationStorageTestHelpers.createTestViolation(ruleID: "refused")],
                for: workspaceId
            )
        }

        let afterFailure = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(Set(afterFailure.map(\.id)) == Set(original.map(\.id)))

        // The failed store left no transaction open, so the next one goes through.
        try await storage.storeViolations([replacement], for: workspaceId)
        let afterRetry = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(afterRetry.map(\.id) == [replacement.id])
    }
}
