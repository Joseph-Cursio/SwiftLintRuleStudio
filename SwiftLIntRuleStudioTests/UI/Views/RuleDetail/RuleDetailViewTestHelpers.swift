//
//  RuleDetailViewTestHelpers.swift
//  SwiftLIntRuleStudioTests
//
//  Helper utilities for RuleDetailView tests
//

import SwiftUI
import ViewInspector
@testable import SwiftLIntRuleStudio

enum RuleDetailViewTestHelpers {
    struct ViewResult: @unchecked Sendable {
        let view: AnyView

        init(view: some View) {
            self.view = AnyView(view)
        }
    }

    struct StubSwiftLintCLI: SwiftLintCLIProtocol {
        func detectSwiftLintPath() throws -> URL { throw SwiftLintError.notFound }
        func executeRulesCommand() throws -> Data { Data() }
        func executeRuleDetailCommand(ruleId: String) throws -> Data { Data() }
        func generateDocsForRule(ruleId: String) throws -> String { "" }
        func executeLintCommand(configPath: URL?, workspacePath: URL) throws -> Data { Data() }
        func getVersion() throws -> String { "0.0.0" }
    }

    @MainActor
    static func createView(
        for rule: Rule,
        rules: [Rule] = [],
        viewModel: RuleDetailViewModel? = nil,
        container: DependencyContainer? = nil
    ) -> ViewResult {
        let cacheManager = CacheManager.createForTesting()
        let ruleRegistry = RuleRegistry(swiftLintCLI: StubSwiftLintCLI(), cacheManager: cacheManager)
        let registryRules = rules.isEmpty ? [rule] : rules
        ruleRegistry.setRulesForTesting(registryRules)

        let resolvedContainer = container ?? DependencyContainer.createForTesting(
            ruleRegistry: ruleRegistry,
            cacheManager: cacheManager
        )

        let detailView = viewModel.map { RuleDetailView(rule: rule, viewModel: $0) }
            ?? RuleDetailView(rule: rule)
        let view = detailView.environmentObject(resolvedContainer)
        return ViewResult(view: view)
    }
}
