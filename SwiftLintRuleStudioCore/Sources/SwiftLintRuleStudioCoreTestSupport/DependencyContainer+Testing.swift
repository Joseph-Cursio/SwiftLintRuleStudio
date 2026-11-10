//
//  DependencyContainer+Testing.swift
//  SwiftLintRuleStudioTests
//

import Foundation
import LintStudioCore
import SwiftLintCLISeam
@testable import SwiftLintRuleStudioCore
import Testing

// Helper to create DependencyContainer with isolated UserDefaults
public extension DependencyContainer {
    /// Creates a DependencyContainer with isolated UserDefaults for testing
    static func createForTesting(
        userDefaults: UserDefaults? = nil,
        ruleRegistry: RuleRegistry? = nil,
        swiftLintCLI: SwiftLintCLIProtocol? = nil,
        cacheManager: CacheManagerProtocol? = nil,
        violationStorage: ViolationStorageProtocol? = nil,
        workspaceManager: WorkspaceManager? = nil,
        onboardingManager: OnboardingManager? = nil,
        impactSimulator: (any ImpactSimulatorProtocol)? = nil
    ) -> DependencyContainer {
        // Create isolated UserDefaults if not provided
        let testUserDefaults = userDefaults
            ?? UserDefaults(suiteName: "test.DependencyContainer.\(UUID().uuidString)")
            ?? .standard

        // Create OnboardingManager with isolated UserDefaults if not provided
        let testOnboardingManager = onboardingManager ?? OnboardingManager(userDefaults: testUserDefaults)

        let testViolationStorage = violationStorage ?? (try? ViolationStorageActor(useInMemory: true))

        return DependencyContainer(
            swiftLintCLI: swiftLintCLI ?? MockSwiftLintCLIActor(),
            ruleRegistry: ruleRegistry,
            cacheManager: cacheManager,
            violationStorage: testViolationStorage,
            workspaceManager: workspaceManager,
            onboardingManager: testOnboardingManager,
            impactSimulator: impactSimulator,
            userDefaults: testUserDefaults
        )
    }
}
