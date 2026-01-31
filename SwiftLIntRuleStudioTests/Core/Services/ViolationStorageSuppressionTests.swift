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
        let (count, isSuppressed, reason) = await MainActor.run {
            (fetched.count, fetched.first?.suppressed, fetched.first?.suppressionReason)
        }
        #expect(count == 1)
        #expect(isSuppressed == true)
        #expect(reason == "Not applicable")
    }

    @Test("ViolationStorage resolves violations")
    func testResolveViolations() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let violations = [ViolationStorageTestHelpers.createTestViolation()]
        try await storage.storeViolations(violations, for: workspaceId)

        try await storage.resolveViolations([violations[0].id])

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        let (count, hasResolvedAt) = await MainActor.run {
            (fetched.count, fetched.first?.resolvedAt != nil)
        }
        #expect(count == 1)
        #expect(hasResolvedAt == true)
    }
}
