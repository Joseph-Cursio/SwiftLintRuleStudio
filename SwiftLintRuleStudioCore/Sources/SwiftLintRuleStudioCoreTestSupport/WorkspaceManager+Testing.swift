//
//  WorkspaceManager+Testing.swift
//  SwiftLintRuleStudioTests
//

@testable import SwiftLintRuleStudioCore

// Extension to WorkspaceManager for test isolation
public extension WorkspaceManager {
    /// Creates a WorkspaceManager with isolated UserDefaults for testing
    /// Uses the test function name to ensure uniqueness
    static func createForTesting(
        testName: String,
        now: DateProvider = .system
    ) -> WorkspaceManager {
        let userDefaults = IsolatedUserDefaults.create(for: testName)
        return WorkspaceManager(userDefaults: userDefaults, now: now)
    }
}
