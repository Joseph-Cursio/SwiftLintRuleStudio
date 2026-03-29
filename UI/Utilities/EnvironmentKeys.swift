//
//  EnvironmentKeys.swift
//  SwiftLintRuleStudio
//
//  Custom SwiftUI environment keys for @Observable services
//

import SwiftUI
import SwiftLintRuleStudioCore

// MARK: - DependencyContainer

private struct DependencyContainerKey: EnvironmentKey {
    @MainActor static var defaultValue: DependencyContainer = DependencyContainer()
}

// MARK: - RuleRegistry

private struct RuleRegistryKey: EnvironmentKey {
    @MainActor static var defaultValue: RuleRegistry = {
        let cache = CacheManager()
        let cli = SwiftLintCLIActor(cacheManager: cache)
        return RuleRegistry(swiftLintCLI: cli, cacheManager: cache)
    }()
}

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
