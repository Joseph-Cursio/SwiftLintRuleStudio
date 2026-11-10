//
//  UIViewTestHelpers.swift
//  SwiftLintRuleStudioTests
//

import SwiftLintCLIBackend
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import SwiftUI
import Testing
import ViewInspector

// Helpers for creating views with proper environment objects
// Using async functions with MainActor.run to allow parallel test execution
enum UIViewTestHelpers {

    /// Creates a DependencyContainer with isolated UserDefaults for testing
    static func createTestDependencyContainer(
        userDefaults: UserDefaults? = nil
    ) async -> DependencyContainer {
        await MainActor.run {
            DependencyContainer.createForTesting(userDefaults: userDefaults)
        }
    }

    /// Creates a view with DependencyContainer as environment object
    @MainActor
    static func createViewWithDependencies<Content: View>(
        _ content: Content,
        dependencyContainer: DependencyContainer? = nil
    ) -> AnyView {
        let container = dependencyContainer ?? DependencyContainer.createForTesting()
        return AnyView(content.environment(\.dependencies, container))
    }

    /// Creates a view with both RuleRegistry and DependencyContainer
    @MainActor
    static func createViewWithFullDependencies<Content: View>(
        _ content: Content,
        dependencyContainer: DependencyContainer? = nil,
        ruleRegistry: RuleRegistry? = nil
    ) -> AnyView {
        let container = dependencyContainer ?? DependencyContainer.createForTesting()
        let cacheManager = CacheManager.createForTesting()
        let swiftLintCLI = SwiftLintCLIActor(cacheManager: cacheManager)
        let registry = ruleRegistry ?? RuleRegistry(swiftLintCLI: swiftLintCLI, cacheManager: cacheManager)

        return AnyView(content
            .environment(\.ruleRegistry, registry)
            .environment(\.dependencies, container))
    }

    /// Creates an OnboardingManager with isolated UserDefaults
    static func createTestOnboardingManager(
        testName: String = UUID().uuidString
    ) async -> OnboardingManager {
        await MainActor.run {
            OnboardingManager.createForTesting(testName: testName)
        }
    }

    /// Creates a WorkspaceManager for testing with isolated UserDefaults
    static func createTestWorkspaceManager(testName: String = UUID().uuidString) async -> WorkspaceManager {
        await MainActor.run {
            WorkspaceManager.createForTesting(testName: testName)
        }
    }
}
