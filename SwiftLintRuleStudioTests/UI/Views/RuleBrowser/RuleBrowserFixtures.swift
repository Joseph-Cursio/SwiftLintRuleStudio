//
//  RuleBrowserFixtures.swift
//  SwiftLintRuleStudioTests
//
//  Shared setup for the RuleBrowserView suites.
//
//  Each of the three suites carried a byte-identical private makeTestRule and
//  — for two of them — a byte-identical ViewResult and createRuleBrowserView.
//  Private, so none could see the others: three implementations of one idea
//  rather than an absence of it.
//

import SwiftLintCLIBackend
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import SwiftUI

enum RuleBrowserFixtures {

    /// A Rule with the browser suites' defaults: no severity of its own and no
    /// default severity, so a test that cares about either has to say so.
    static func makeTestRule(
        id: String = "test_rule",
        name: String = "Test Rule",
        description: String = "Test description",
        category: RuleCategory = .lint,
        isOptIn: Bool = false,
        isEnabled: Bool = false
    ) -> Rule {
        Rule(
            id: id,
            name: name,
            description: description,
            category: category,
            isOptIn: isOptIn,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: isEnabled,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: nil
        )
    }

    /// Workaround for Swift 6 strict concurrency: return a ViewResult rather
    /// than a tuple carrying `some View`.
    @MainActor
    struct ViewResult: @unchecked Sendable {
        let view: AnyView
        let container: DependencyContainer

        init(view: some View, container: DependencyContainer) {
            self.view = AnyView(view)
            self.container = container
        }
    }

    /// A RuleBrowserView over a registry seeded with `rules`, built through the
    /// `ruleRegistry:` initialiser.
    ///
    /// `RuleBrowserViewInteractionTests` deliberately keeps its own builder: it
    /// goes through `RuleBrowserView(viewModel:)` and needs the view model back,
    /// which is a different initialiser under test, not a copy of this one.
    @MainActor
    static func makeView(rules: [Rule] = []) -> ViewResult {
        let container = DependencyContainer.createForTesting()
        let cacheManager = CacheManager.createForTesting()
        let swiftLintCLI = SwiftLintCLIActor(cacheManager: cacheManager)
        let ruleRegistry = RuleRegistry(swiftLintCLI: swiftLintCLI, cacheManager: cacheManager)
        #if DEBUG
        if !rules.isEmpty {
            ruleRegistry.setRulesForTesting(rules)
        }
        #endif
        let view = RuleBrowserView(ruleRegistry: ruleRegistry)
            .environment(\.ruleRegistry, ruleRegistry)
            .environment(\.dependencies, container)
        return ViewResult(view: view, container: container)
    }
}
