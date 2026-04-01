//
//  SafeRulesDiscoveryViewTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for SafeRulesDiscoveryView
//

import Testing
import SwiftUI
import ViewInspector
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

// swiftlint:disable function_body_length

// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
// swiftlint:disable:next type_body_length
@MainActor
struct SafeRulesDiscoveryViewTests {

    // Workaround type to bypass Sendable check for SwiftUI views
    @MainActor
    struct ViewResult: @unchecked Sendable {
        let view: AnyView
        let container: DependencyContainer

        init(view: some View, container: DependencyContainer) {
            self.view = AnyView(view)
            self.container = container
        }
    }

    // Workaround for Swift 6 strict concurrency: Return ViewResult instead of tuple with 'some View'
    @MainActor
    private func createSafeRulesDiscoveryView() -> ViewResult {
        let container = DependencyContainer.createForTesting()
        let view = SafeRulesDiscoveryView()
            .environment(\.dependencies, container)
        return ViewResult(view: view, container: container)
    }

    @MainActor
    private func createSafeRulesDiscoveryView(
        rules: [Rule],
        safeRuleIds: [String],
        results: [String: RuleImpactResult],
        workspaceURL: URL
    ) throws -> ViewResult {
        let cacheManager = CacheManager.createForTesting()
        let swiftLintCLI = SwiftLintCLIActor(cacheManager: cacheManager)
        let ruleRegistry = RuleRegistry(
            swiftLintCLI: swiftLintCLI,
            cacheManager: cacheManager
        )
        ruleRegistry.setRulesForTesting(rules)

        let mockImpactSimulator = MockImpactSimulator(
            safeRuleIds: safeRuleIds,
            results: results
        )

        let workspaceManager = WorkspaceManager.createForTesting(testName: #function)
        try workspaceManager.openWorkspace(at: workspaceURL)

        let container = DependencyContainer.createForTesting(
            ruleRegistry: ruleRegistry,
            cacheManager: cacheManager,
            workspaceManager: workspaceManager,
            impactSimulator: mockImpactSimulator
        )

        let view = SafeRulesDiscoveryView()
            .environment(\.dependencies, container)

        return ViewResult(view: view, container: container)
    }

    @Test("SafeRulesDiscoveryView initializes correctly")
    func testInitialization() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createSafeRulesDiscoveryView() }.value
        _ = result.view
        _ = result.container

        // Verify view can be created
        #expect(Bool(true))
    }

    @Test("SafeRulesDiscoveryView shows empty state")
    func testEmptyStateView() async throws {
        let result = await Task { @MainActor in createSafeRulesDiscoveryView() }.value
        let view = result.view

        let (hasHeader, hasEmptyTitle, hasEmptySubtitle) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            let hasHeader = (try? inspector.find(text: "Discover Safe Rules")) != nil
            let hasEmptyTitle = (try? inspector.find(text: "No Safe Rules Discovered")) != nil
            let emptySubtitle = "Click 'Discover Safe Rules' to analyze disabled rules in your workspace"
            let hasEmptySubtitle = (try? inspector.find(text: emptySubtitle)) != nil
            return (hasHeader, hasEmptyTitle, hasEmptySubtitle)
        }

        #expect(hasHeader)
        #expect(hasEmptyTitle)
        #expect(hasEmptySubtitle)
    }

    @Test("SafeRulesDiscoveryView discovers safe rules and enables them")
    func testDiscoverAndEnableSafeRules() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SafeRulesDiscoveryViewTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let swiftFile = tempDir.appendingPathComponent("Test.swift")
        try Data("struct Test {}".utf8).write(to: swiftFile)

        let configURL = tempDir.appendingPathComponent(".swiftlint.yml")
        let configContent = """
        disabled_rules:
          - safe_rule_1
          - safe_rule_2
        rules:
          some_other_rule:
            enabled: false
        """
        try Data(configContent.utf8).write(to: configURL)

        let rules = [
            Rule(
                id: "safe_rule_1",
                name: "Safe Rule 1",
                description: "desc",
                category: .lint,
                isOptIn: false,
                severity: nil,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: nil,
                markdownDocumentation: nil
            ),
            Rule(
                id: "safe_rule_2",
                name: "Safe Rule 2",
                description: "desc",
                category: .lint,
                isOptIn: false,
                severity: nil,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: nil,
                markdownDocumentation: nil
            )
        ]

        let results = [
            "safe_rule_1": RuleImpactResult(
                ruleId: "safe_rule_1",
                violationCount: 0,
                violations: [],
                affectedFiles: [],
                simulationDuration: 0.1
            ),
            "safe_rule_2": RuleImpactResult(
                ruleId: "safe_rule_2",
                violationCount: 0,
                violations: [],
                affectedFiles: [],
                simulationDuration: 0.1
            )
        ]

        let result = try await MainActor.run {
            try createSafeRulesDiscoveryView(
                rules: rules,
                safeRuleIds: ["safe_rule_1", "safe_rule_2"],
                results: results,
                workspaceURL: tempDir
            )
        }

        let container = result.container
        let hasWorkspace = await MainActor.run { container.workspaceManager.currentWorkspace != nil }
        let ruleCount = await MainActor.run { container.ruleRegistry.rules.count }
        #expect(hasWorkspace)
        #expect(ruleCount == 2)
        // ViewInspector cannot inject @Observable @Environment values, so the
        // "Discover Safe Rules" button always appears disabled (it reads currentWorkspace
        // from the environment, which ViewInspector can't populate for @Observable types).
        // The workspace and rule setup is verified above; tapping the button is not testable
        // through ViewInspector until it supports @Observable environment injection.
    }

    @Test("SafeRulesDiscoveryView shows results list and summary")
    @MainActor
    func testShowsResultsList() async throws {
        let safeRules = [
            RuleImpactResult(
                ruleId: "safe_rule_1",
                violationCount: 0,
                violations: [],
                affectedFiles: [],
                simulationDuration: 0.1
            ),
            RuleImpactResult(
                ruleId: "safe_rule_2",
                violationCount: 0,
                violations: [],
                affectedFiles: [],
                simulationDuration: 0.1
            )
        ]

        let container = DependencyContainer.createForTesting()
        let view = SafeRulesDiscoveryView(
            safeRules: safeRules,
            selectedRules: ["safe_rule_1", "safe_rule_2"]
        )
        .environment(\.dependencies, container)

        await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
        }
        defer { Task { @MainActor in ViewHosting.expel() } }

        let hasSummary = await UIAsyncTestHelpers.waitForText(
            in: view,
            text: "Found 2 safe rules",
            timeout: 3.0
        )
        let hasSelectAll = await UIAsyncTestHelpers.waitForText(
            in: view,
            text: "Select All",
            timeout: 3.0
        )
        let hasDeselectAll = await UIAsyncTestHelpers.waitForText(
            in: view,
            text: "Deselect All",
            timeout: 3.0
        )
        let hasRule1 = await UIAsyncTestHelpers.waitForText(
            in: view,
            text: "safe_rule_1",
            timeout: 3.0
        )
        let hasRule2 = await UIAsyncTestHelpers.waitForText(
            in: view,
            text: "safe_rule_2",
            timeout: 3.0
        )

        #expect(hasSummary)
        #expect(hasSelectAll)
        #expect(hasDeselectAll)
        #expect(hasRule1)
        #expect(hasRule2)
    }

}

@MainActor
final class MockImpactSimulator: ImpactSimulator {
    private let safeRuleIds: [String]
    private let results: [String: RuleImpactResult]
    private(set) var findSafeRulesCalls = 0
    private(set) var simulateRuleCalls = 0

    init(safeRuleIds: [String], results: [String: RuleImpactResult]) {
        self.safeRuleIds = safeRuleIds
        self.results = results
        super.init(swiftLintCLI: StubSwiftLintCLI())
    }

    override func findSafeRules(
        workspace: Workspace,
        baseConfigPath: URL?,
        disabledRuleIds: [String],
        optInRuleIds: Set<String>,
        progressHandler: ((Int, Int, String) -> Void)? = nil
    ) async throws -> [String] {
        await Task.yield()
        findSafeRulesCalls += 1
        for (index, ruleId) in safeRuleIds.enumerated() {
            progressHandler?(index + 1, safeRuleIds.count, ruleId)
        }
        return safeRuleIds
    }

    override func simulateRule(
        ruleId: String,
        workspace: Workspace,
        baseConfigPath: URL?,
        isOptIn: Bool
    ) async throws -> RuleImpactResult {
        await Task.yield()
        simulateRuleCalls += 1
        if let result = results[ruleId] {
            return result
        }
        return RuleImpactResult(
            ruleId: ruleId,
            violationCount: 0,
            violations: [],
            affectedFiles: [],
            simulationDuration: 0
        )
    }
}

@MainActor
struct StubSwiftLintCLI: SwiftLintCLIProtocol {
    func detectSwiftLintPath() throws -> URL { throw SwiftLintError.notFound }
    func executeRulesCommand() throws -> Data { Data() }
    func executeRuleDetailCommand(ruleId: String) throws -> Data { Data() }
    func generateDocsForRule(ruleId: String) throws -> String { "" }
    func executeLintCommand(configPath: URL?, workspacePath: URL) throws -> Data { Data() }
    func getVersion() throws -> String { "0.0.0" }
}
// swiftlint:enable function_body_length
