//
//  ViolationStorageFilterTests.swift
//  SwiftLintRuleStudioTests
//
//  File, severity and suppression filter tests for ViolationStorageActor
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct ViolationStorageFilterTests {
    private static func violation(
        file: String,
        severity: Severity = .warning,
        suppressed: Bool = false
    ) -> Violation {
        Violation(
            ruleID: "test_rule",
            filePath: file,
            line: 1,
            severity: severity,
            message: "Test violation",
            suppressed: suppressed
        )
    }

    /// Storage holding one violation in each of A.swift, B.swift and C.swift.
    private static func storageWithThreeFiles() async throws -> (ViolationStorageActor, UUID) {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()
        try await storage.storeViolations(
            ["A.swift", "B.swift", "C.swift"].map { violation(file: $0) },
            for: workspaceId
        )
        return (storage, workspaceId)
    }

    @Test("ViolationStorageActor keeps only the violations in the given files")
    func testFilePathsFilter() async throws {
        let (storage, workspaceId) = try await Self.storageWithThreeFiles()
        let filter = ViolationFilter(filePaths: ["A.swift", "C.swift"])

        let fetched = try await storage.fetchViolations(filter: filter, workspaceId: workspaceId)
        #expect(Set(fetched.map(\.filePath)) == ["A.swift", "C.swift"])
        #expect(try await storage.getViolationCount(filter: filter, workspaceId: workspaceId) == 2)
    }

    @Test("ViolationStorageActor treats an empty file list as no file filter")
    func testEmptyFilePathsFilter() async throws {
        let (storage, workspaceId) = try await Self.storageWithThreeFiles()

        let fetched = try await storage.fetchViolations(
            filter: ViolationFilter(filePaths: []),
            workspaceId: workspaceId
        )
        #expect(fetched.count == 3)
    }

    @Test("ViolationStorageActor keeps only the violations of the given severities")
    func testSeveritiesFilter() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()
        try await storage.storeViolations(
            [
                Self.violation(file: "A.swift", severity: .warning),
                Self.violation(file: "B.swift", severity: .error),
                Self.violation(file: "C.swift", severity: .warning)
            ],
            for: workspaceId
        )

        let errors = ViolationFilter(severities: [.error])
        let fetched = try await storage.fetchViolations(filter: errors, workspaceId: workspaceId)
        #expect(fetched.map(\.filePath) == ["B.swift"])
        #expect(try await storage.getViolationCount(filter: errors, workspaceId: workspaceId) == 1)

        let unfiltered = try await storage.fetchViolations(
            filter: ViolationFilter(severities: []),
            workspaceId: workspaceId
        )
        #expect(unfiltered.count == 3)
    }

    @Test("ViolationStorageActor keeps only suppressed, or only unsuppressed, violations")
    func testSuppressedOnlyFilter() async throws {
        let storage = try await ViolationStorageTestHelpers.createIsolatedStorage()
        let workspaceId = UUID()
        try await storage.storeViolations(
            [
                Self.violation(file: "Suppressed.swift", suppressed: true),
                Self.violation(file: "Open.swift"),
                Self.violation(file: "AlsoOpen.swift")
            ],
            for: workspaceId
        )

        let suppressed = try await storage.fetchViolations(
            filter: ViolationFilter(suppressedOnly: true),
            workspaceId: workspaceId
        )
        #expect(suppressed.map(\.filePath) == ["Suppressed.swift"])

        let open = try await storage.fetchViolations(
            filter: ViolationFilter(suppressedOnly: false),
            workspaceId: workspaceId
        )
        #expect(Set(open.map(\.filePath)) == ["Open.swift", "AlsoOpen.swift"])
    }
}
