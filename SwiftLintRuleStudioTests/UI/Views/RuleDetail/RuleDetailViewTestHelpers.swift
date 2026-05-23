//
//  RuleDetailViewTestHelpers.swift
//  SwiftLintRuleStudioTests
//
//  Helper utilities for RuleDetailView tests
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import SwiftUI
import ViewInspector

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
        func executeRuleDetailCommand(ruleId _: String) throws -> Data { Data() }
        func generateDocsForRule(ruleId _: String) throws -> String { "" }
        func executeLintCommand(configPath _: URL?, workspacePath _: URL) throws -> Data { Data() }
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
        let view = detailView.environment(\.dependencies, resolvedContainer)
        return ViewResult(view: view)
    }
}
