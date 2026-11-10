//
//  EnvironmentValues+Dependencies.swift
//  SwiftLintRuleStudio
//

import SwiftLintRuleStudioCore
import SwiftUI

/// The environment keys behind the values the extension below adds.
private enum DependencyKeys {
    struct Container: EnvironmentKey {
        // Backend-agnostic default: real app targets inject a concrete backend at the
        // app root (subprocess for Studio, in-process for Explorer). This no-op default
        // exists only so the shared UI compiles in either target without naming one.
        @MainActor static var defaultValue = DependencyContainer(
            swiftLintCLI: UnconfiguredSwiftLintBackend()
        )
    }

    struct Registry: EnvironmentKey {
        @MainActor static var defaultValue: RuleRegistry = {
            // An `EnvironmentKey.defaultValue` is the environment's composition root: the value
            // used when no app target has injected one, which is what the comment on
            // `Container` above describes for the backend. Injecting a cache manager
            // into the default would mean routing it in from somewhere there is no somewhere.
            // swiftprojectlint:disable:next direct-instantiation
            let cache = CacheManager()
            let cli = UnconfiguredSwiftLintBackend()
            return RuleRegistry(swiftLintCLI: cli, cacheManager: cache)
        }()
    }

    struct Capabilities: EnvironmentKey {
        // Default to the full set (Studio). The sandboxed Explorer target injects a
        // reduced set (empty) at its app root.
        nonisolated static let defaultValue: Set<AppCapability> = Set(AppCapability.allCases)
    }
}

extension EnvironmentValues {
    var dependencies: DependencyContainer {
        get { self[DependencyKeys.Container.self] }
        set { self[DependencyKeys.Container.self] = newValue }
    }

    var ruleRegistry: RuleRegistry {
        get { self[DependencyKeys.Registry.self] }
        set { self[DependencyKeys.Registry.self] = newValue }
    }

    /// Edition-specific capabilities (full in Studio, reduced in the sandboxed
    /// Explorer). Shared UI conditions external-tool features on these.
    var appCapabilities: Set<AppCapability> {
        get { self[DependencyKeys.Capabilities.self] }
        set { self[DependencyKeys.Capabilities.self] = newValue }
    }
}
