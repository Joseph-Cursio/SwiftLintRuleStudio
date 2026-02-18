//
//  ViolationStorageSuppressionTests.swift
//  SwiftLIntRuleStudioTests
//
//  Suppression and resolution tests for ViolationStorage
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct ViolationStorageSuppressionTests {
    @Test("ViolationStorage suppresses violations")
    func testSuppressViolations() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let violations = [ViolationStorageTestHelpers.createTestViolation()]
        try await storage.storeViolations(violations, for: workspaceId)

        try await storage.suppressViolations([violations[0].id], reason: "Not applicable")

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 1)
        #expect(fetched.first?.suppressed == true)
        #expect(fetched.first?.suppressionReason == "Not applicable")
    }

    @Test("ViolationStorage resolves violations")
    func testResolveViolations() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let violations = [ViolationStorageTestHelpers.createTestViolation()]
        try await storage.storeViolations(violations, for: workspaceId)

        try await storage.resolveViolations([violations[0].id])

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 1)
        #expect(fetched.first?.resolvedAt != nil)
    }
}
