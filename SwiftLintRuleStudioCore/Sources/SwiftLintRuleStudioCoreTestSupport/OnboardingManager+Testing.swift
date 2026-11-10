//
//  OnboardingManager+Testing.swift
//  SwiftLintRuleStudioTests
//

@testable import SwiftLintRuleStudioCore

// Extension to OnboardingManager for test isolation
public extension OnboardingManager {
    /// Creates an OnboardingManager with isolated UserDefaults for testing
    static func createForTesting(testName: String) -> OnboardingManager {
        let userDefaults = IsolatedUserDefaults.create(for: testName)
        return OnboardingManager(userDefaults: userDefaults)
    }
}
