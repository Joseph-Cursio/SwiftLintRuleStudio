//
//  IsolatedUserDefaults.swift
//  SwiftLintRuleStudioTests
//

import Foundation

/// Provides isolated UserDefaults instances for each test to prevent cross-test contamination
public enum IsolatedUserDefaults {
    /// Creates a unique UserDefaults suite for the current test
    /// Uses the test function name to ensure uniqueness
    public static func create(for testName: String) -> UserDefaults {
        // Use test name + UUID to ensure complete isolation
        let suiteName = "test.\(testName).\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create UserDefaults suite: \(suiteName)")
        }
        return userDefaults
    }

    /// Cleans up a UserDefaults suite
    /// Note: UserDefaults doesn't expose suiteName, so we remove all keys manually
    public static func cleanup(_ userDefaults: UserDefaults) {
        // Remove all keys from the suite
        // We can't get the suite name directly, so we remove the onboarding key
        // In practice, each test uses a unique suite, so this is sufficient
        userDefaults.removeObject(forKey: "com.swiftlintrulestudio.hasCompletedOnboarding")
        // Remove any other test-specific keys if needed
        userDefaults.synchronize()
    }
}
