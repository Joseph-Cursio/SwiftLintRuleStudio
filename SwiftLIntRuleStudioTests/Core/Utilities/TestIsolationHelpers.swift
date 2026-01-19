//
//  TestIsolationHelpers.swift
//  SwiftLIntRuleStudioTests
//
//  Reusable helpers for test isolation using Swift Testing framework features
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

/// Provides isolated UserDefaults for each test
/// Uses Swift Testing's test name to create unique suite names
struct IsolatedUserDefaults {
    /// Creates a unique UserDefaults suite for the current test
    /// Uses the test function name to ensure uniqueness
    static func create(for testName: String) -> UserDefaults {
        // Use test name + UUID to ensure complete isolation
        let suiteName = "test.\(testName).\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create UserDefaults suite: \(suiteName)")
        }
        return userDefaults
    }
    
    /// Creates a shared UserDefaults suite for a test suite
    /// Useful when tests need to share state within a suite but isolate from others
    static func createShared(for suiteName: String) -> UserDefaults {
        let fullSuiteName = "test.shared.\(suiteName)"
        guard let userDefaults = UserDefaults(suiteName: fullSuiteName) else {
            fatalError("Failed to create shared UserDefaults suite: \(fullSuiteName)")
        }
        return userDefaults
    }
    
    /// Cleans up a UserDefaults suite
    /// Note: UserDefaults doesn't expose suiteName, so we remove all keys manually
    static func cleanup(_ userDefaults: UserDefaults) {
        // Remove all keys from the suite
        // We can't get the suite name directly, so we remove the onboarding key
        // In practice, each test uses a unique suite, so this is sufficient
        userDefaults.removeObject(forKey: "com.swiftlintrulestudio.hasCompletedOnboarding")
        // Remove any other test-specific keys if needed
        userDefaults.synchronize()
    }
}

/// Helper to create DependencyContainer with isolated UserDefaults
extension DependencyContainer {
    /// Creates a DependencyContainer with isolated UserDefaults for testing
    static func createForTesting(
        userDefaults: UserDefaults? = nil,
        ruleRegistry: RuleRegistry? = nil,
        swiftLintCLI: SwiftLintCLIProtocol? = nil,
        cacheManager: CacheManagerProtocol? = nil,
        violationStorage: ViolationStorageProtocol? = nil,
        workspaceManager: WorkspaceManager? = nil,
        onboardingManager: OnboardingManager? = nil,
        impactSimulator: ImpactSimulator? = nil
    ) -> DependencyContainer {
        // Create isolated UserDefaults if not provided
        let testUserDefaults = userDefaults ?? UserDefaults(suiteName: "test.DependencyContainer.\(UUID().uuidString)")!
        
        // Create OnboardingManager with isolated UserDefaults if not provided
        let testOnboardingManager = onboardingManager ?? OnboardingManager(userDefaults: testUserDefaults)
        
        let testViolationStorage = violationStorage ?? (try? ViolationStorage(useInMemory: true))
        
        return DependencyContainer(
            ruleRegistry: ruleRegistry,
            swiftLintCLI: swiftLintCLI,
            cacheManager: cacheManager,
            violationStorage: testViolationStorage,
            workspaceManager: workspaceManager,
            onboardingManager: testOnboardingManager,
            impactSimulator: impactSimulator,
            userDefaults: testUserDefaults
        )
    }
}

/// Extension to OnboardingManager for test isolation
extension OnboardingManager {
    /// Creates an OnboardingManager with isolated UserDefaults for testing
    static func createForTesting(testName: String) -> OnboardingManager {
        let userDefaults = IsolatedUserDefaults.create(for: testName)
        return OnboardingManager(userDefaults: userDefaults)
    }
}

/// Extension to WorkspaceManager for test isolation
extension WorkspaceManager {
    /// Creates a WorkspaceManager with isolated UserDefaults for testing
    /// Uses the test function name to ensure uniqueness
    static func createForTesting(testName: String) -> WorkspaceManager {
        let userDefaults = IsolatedUserDefaults.create(for: testName)
        return WorkspaceManager(userDefaults: userDefaults)
    }
}

/// Extension to CacheManager for test isolation
extension CacheManager {
    /// Creates a CacheManager with isolated cache directory for testing
    /// Uses UUID to ensure complete isolation between tests
    static func createForTesting() -> CacheManager {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return CacheManager(cacheDirectory: tempDir)
    }
}

/// Extension to FileTracker for test isolation
extension FileTracker {
    /// Creates a FileTracker with isolated cache file for testing
    /// Uses UUID to ensure complete isolation between tests
    /// Note: FileTracker is @MainActor, so this must be called from MainActor context
    @MainActor
    static func createForTesting() -> FileTracker {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let cacheURL = tempDir.appendingPathComponent("file_tracker_cache.json")
        return FileTracker(cacheURL: cacheURL)
    }
}

// Note: Swift Testing framework provides isolation by default:
// 1. Each test gets a fresh struct instance (no shared state)
// 2. Tests run in parallel by default (helps identify isolation issues)
// 3. For sequential execution, you can use test arguments or organize tests into suites
//
// If you need sequential execution for specific tests, consider:
// - Using test arguments to control execution order
// - Organizing related tests into separate test files
// - Using shared isolated resources (like UserDefaults suites) when needed

