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
    @MainActor static var defaultValue = DependencyContainer()
}

// MARK: - RuleRegistry

private struct RuleRegistryKey: EnvironmentKey {
    @MainActor static var defaultValue: RuleRegistry = {
        let cache = CacheManager()
        let cli = SwiftLintCLIActor(cacheManager: cache)
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
