//
//  ViolationStorageMetadataTests.swift
//  SwiftLIntRuleStudioTests
//
//  Metadata and ID handling tests for ViolationStorage
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct ViolationStorageMetadataTests {
    @Test("ViolationStorage preserves violation metadata")
    func testPreserveViolationMetadata() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let original = Violation(
            id: UUID(),
            ruleID: "test_rule",
            filePath: "Test.swift",
            line: 42,
            column: 10,
            severity: .warning,
            message: "Test message",
            detectedAt: Date(),
            resolvedAt: nil,
            suppressed: false,
            suppressionReason: nil
        )

        try await storage.storeViolations([original], for: workspaceId)
        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        let captured = await MainActor.run {
            fetched.first.map { violation in
                CapturedViolation(
                    count: fetched.count,
                    metadata: MetadataSnapshot(
                        id: violation.id,
                        ruleID: violation.ruleID,
                        filePath: violation.filePath,
                        line: violation.line,
                        column: violation.column,
                        severity: violation.severity,
                        message: violation.message
                    )
                )
            }
        }

        let unwrapped = try #require(captured)
        let expected = await MainActor.run {
            MetadataSnapshot(
                id: original.id,
                ruleID: original.ruleID,
                filePath: original.filePath,
                line: original.line,
                column: original.column,
                severity: original.severity,
                message: original.message
            )
        }
        assertMetadataMatches(expected: expected, captured: unwrapped)
        #expect(unwrapped.count == 1)
    }

    @Test("ViolationStorage handles duplicate IDs with INSERT OR REPLACE")
    func testDuplicateIDsAreReplaced() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let sharedID = UUID()
        let violation1 = Violation(
            id: sharedID,
            ruleID: "rule1",
            filePath: "File1.swift",
            line: 10,
            severity: .error,
            message: "First message"
        )

        let violation2 = Violation(
            id: sharedID,
            ruleID: "rule2",
            filePath: "File2.swift",
            line: 20,
            severity: .warning,
            message: "Second message"
        )

        try await storage.storeViolations([violation1, violation2], for: workspaceId)

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 1)

        let stored = await MainActor.run {
            fetched.first.map { ($0.id, $0.ruleID, $0.filePath, $0.message) }
        }
        let unwrapped = try #require(stored)
        #expect(unwrapped.0 == sharedID)
        #expect(unwrapped.1 == "rule2")
        #expect(unwrapped.2 == "File2.swift")
        #expect(unwrapped.3 == "Second message")
    }

    @Test("ViolationStorage ensures all violations have unique IDs")
    func testAllViolationsHaveUniqueIDs() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()

        let violations = (0..<100).map { index in
            ViolationStorageTestHelpers.createTestViolation(
                ruleID: "rule\(index)",
                filePath: "File\(index).swift"
            )
        }

        let ids = await MainActor.run { Set(violations.map { $0.id }) }
        #expect(ids.count == 100, "All violations should have unique IDs")

        try await storage.storeViolations(violations, for: workspaceId)

        let fetched = try await storage.fetchViolations(filter: .all, workspaceId: workspaceId)
        #expect(fetched.count == 100)

        let fetchedIDs = await MainActor.run { Set(fetched.map { $0.id }) }
        #expect(fetchedIDs.count == 100, "All fetched violations should have unique IDs")
    }

    private struct MetadataSnapshot: Equatable {
        let id: UUID
        let ruleID: String
        let filePath: String
        let line: Int
        let column: Int?
        let severity: Severity
        let message: String
    }

    private struct CapturedViolation {
        let count: Int
        let metadata: MetadataSnapshot
    }

    private func assertMetadataMatches(
        expected: MetadataSnapshot,
        captured: CapturedViolation
    ) {
        #expect(captured.metadata == expected)
    }
}
