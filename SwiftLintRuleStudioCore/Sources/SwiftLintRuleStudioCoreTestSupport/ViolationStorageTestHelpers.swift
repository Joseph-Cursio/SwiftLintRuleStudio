//
//  ViolationStorageTestHelpers.swift
//  SwiftLintRuleStudioTests
//
//  Helper utilities for ViolationStorageActor tests
//

import Foundation
@testable import SwiftLintRuleStudioCore

public enum ViolationStorageTestHelpers {
    public static func createIsolatedStorage() async throws -> ViolationStorageActor {
        try await Task.detached {
            try await ViolationStorageActor(useInMemory: true)
        }.value
    }

    public static func createTempDatabase() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        return tempDir.appendingPathComponent("test_violations.db")
    }

    public static func cleanupTempDatabase(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    public static func createTestViolation(
        ruleID: String = "test_rule",
        filePath: String = "Test.swift"
    ) -> Violation {
        Violation(
            ruleID: ruleID,
            filePath: filePath,
            line: 10,
            column: 5,
            severity: .error,
            message: "Test violation"
        )
    }
}
