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

// MARK: - App Capabilities

private struct AppCapabilitiesKey: EnvironmentKey {
    // Default to the full set (Studio). The sandboxed Explorer target injects a
    // reduced set (empty) at its app root.
    nonisolated static let defaultValue: Set<AppCapability> = Set(AppCapability.allCases)
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

    /// Edition-specific capabilities (full in Studio, reduced in the sandboxed
    /// Explorer). Shared UI conditions external-tool features on these.
    var appCapabilities: Set<AppCapability> {
        get { self[AppCapabilitiesKey.self] }
        set { self[AppCapabilitiesKey.self] = newValue }
    }
}
