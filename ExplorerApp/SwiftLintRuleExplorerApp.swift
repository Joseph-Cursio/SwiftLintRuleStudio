//
//  SwiftLintRuleExplorerApp.swift
//  SwiftLintRuleExplorer
//
//  Entry point for the sandboxed (Mac App Store) edition. Identical shared UI
//  to Studio, but its composition root injects the in-process SwiftLint backend
//  instead of the subprocess one — no external `swiftlint` binary, so it runs
//  under the App Sandbox.
//

import SwiftUI
import SwiftLintRuleStudioCore
import SwiftLintInProcessBackend

@main
struct SwiftLintRuleExplorerApp: App {
    @State private var ruleRegistry: RuleRegistry
    @State private var dependencyContainer: DependencyContainer

    init() {
        // Set the sandbox-safety env vars (SWIFTLINT_DISABLE_SOURCEKIT +
        // SWIFTLINT_SWIFT_VERSION) BEFORE any SwiftLintFramework symbol is touched.
        // A GUI .app doesn't inherit shell env, so this must happen in code, first.
        SwiftLintInProcessActor.prepare()

        let cacheManager = CacheManager()
        let backend = SwiftLintInProcessActor()
        let registry = RuleRegistry(swiftLintCLI: backend, cacheManager: cacheManager)
        // Sandboxed: persist security-scoped bookmarks so recent workspaces can be
        // reopened across launches.
        let workspaceManager = WorkspaceManager(
            userDefaults: .standard, bookmarkStore: UserDefaultsBookmarkStore())
        let container = DependencyContainer(
            ruleRegistry: registry, swiftLintCLI: backend, cacheManager: cacheManager,
            workspaceManager: workspaceManager)

        _ruleRegistry = State(initialValue: registry)
        _dependencyContainer = State(initialValue: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.ruleRegistry, ruleRegistry)
                .environment(\.dependencies, dependencyContainer)
        }
        .defaultSize(width: 1_100, height: 700)
        .windowResizability(.contentMinSize)
    }
}
