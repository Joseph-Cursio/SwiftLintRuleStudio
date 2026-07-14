//
//  EnvironmentKeys.swift
//  SwiftLintRuleStudio
//
//  Custom SwiftUI environment keys for @Observable services
//

import SwiftLintRuleStudioCore
import SwiftUI

// MARK: - DependencyContainer

private struct DependencyContainerKey: EnvironmentKey {
    // Backend-agnostic default: real app targets inject a concrete backend at the
    // app root (subprocess for Studio, in-process for Explorer). This no-op default
    // exists only so the shared UI compiles in either target without naming one.
    @MainActor static var defaultValue = DependencyContainer(
        swiftLintCLI: UnconfiguredSwiftLintBackend())
}

// MARK: - RuleRegistry

private struct RuleRegistryKey: EnvironmentKey {
    @MainActor static var defaultValue: RuleRegistry = {
        let cache = CacheManager()
        let cli = UnconfiguredSwiftLintBackend()
        return RuleRegistry(swiftLintCLI: cli, cacheManager: cache)
    }()
}

// MARK: - File marker (satisfies file_name lint rule)

private enum EnvironmentKeys {}

// MARK: - EnvironmentValues

extension EnvironmentValues {
    var dependencies: DependencyContainer {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }

    var ruleRegistry: RuleRegistry {
        get { self[RuleRegistryKey.self] }
        set { self[RuleRegistryKey.self] = newValue }
    }
}
