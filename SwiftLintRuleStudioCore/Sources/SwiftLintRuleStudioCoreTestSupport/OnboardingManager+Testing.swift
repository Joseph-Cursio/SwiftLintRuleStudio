//
//  OnboardingManager+Testing.swift
//  SwiftLintRuleStudioTests
//

import Foundation
import LintStudioCore
import SwiftLintCLISeam
@testable import SwiftLintRuleStudioCore
import Testing

// Extension to OnboardingManager for test isolation
public extension OnboardingManager {
    /// Creates an OnboardingManager with isolated UserDefaults for testing
    static func createForTesting(testName: String) -> OnboardingManager {
        let userDefaults = IsolatedUserDefaults.create(for: testName)
        return OnboardingManager(userDefaults: userDefaults)
    }
}
