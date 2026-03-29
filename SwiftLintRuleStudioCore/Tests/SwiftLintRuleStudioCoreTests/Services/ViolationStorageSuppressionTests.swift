//
//  ViolationStorageSuppressionTests.swift
//  SwiftLintRuleStudioTests
//
//  Suppression and resolution tests for ViolationStorageActor
//

import Foundation
import Testing
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport

struct ViolationStorageSuppressionTests {
    @Test("ViolationStorageActor suppresses violations")
    func testSuppressViolations() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let violations = [ViolationStorageTestHelpers.createTestViolation()]
        try await storage.storeViolations(violations, for: workspaceId)

        try await storage.suppressViolations([violations[0].id], reason: "Not applicable")

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 1)
        let violation = try #require(fetched.first)
        #expect(violation.suppressed)
        #expect(violation.suppressionReason == "Not applicable")
    }

    @Test("ViolationStorageActor resolves violations")
    func testResolveViolations() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let violations = [ViolationStorageTestHelpers.createTestViolation()]
        try await storage.storeViolations(violations, for: workspaceId)

        try await storage.resolveViolations([violations[0].id])

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 1)
        let violation = try #require(fetched.first)
        #expect(violation.resolvedAt != nil)
    }
}
