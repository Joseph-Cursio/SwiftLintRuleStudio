//
//  RuleAuditViewTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for RuleAuditView
//

import Testing
import SwiftUI
import ViewInspector
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

// swiftlint:disable function_body_length

@MainActor // swiftlint:disable:next type_body_length
struct RuleAuditViewTests {

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
    private func createRuleAuditView() -> ViewResult {
        let container = DependencyContainer.createForTesting()
        let view = RuleAuditView()
            .environment(\.dependencies, container)
        return ViewResult(view: view, container: container)
    }

    @MainActor
    private func createRuleAuditView(
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

        let view = RuleAuditView()
            .environment(\.dependencies, container)

        return ViewResult(view: view, container: container)
    }

    @Test("RuleAuditView initializes correctly")
    func testInitialization() async throws {
        let result = await Task { @MainActor in createRuleAuditView() }.value
        _ = result.view
        _ = result.container

        // Verify view can be created
        #expect(Bool(true))
    }

    @Test("RuleAuditView shows empty state")
    func testEmptyStateView() async throws {
        let result = await Task { @MainActor in createRuleAuditView() }.value
        let view = result.view

        let (hasEmptyTitle, hasEmptySubtitle) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            let hasEmptyTitle = (try? inspector.find(text: "No Audit Results")) != nil
            let emptySubtitle = "Click 'Run Audit' to test disabled rules against your workspace"
            let hasEmptySubtitle = (try? inspector.find(text: emptySubtitle)) != nil
            return (hasEmptyTitle, hasEmptySubtitle)
        }

        #expect(hasEmptyTitle)
        #expect(hasEmptySubtitle)
    }

    @Test("RuleAuditView can be configured with workspace and rules")
    func testWithWorkspaceAndRules() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuleAuditViewTests", isDirectory: true)
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
            try createRuleAuditView(
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
    }

    @Test("RuleAuditView shows summary cards and status bar with pre-populated entries")
    @MainActor
    func testShowsSummaryAndStatusBar() async throws {
        let entries = [
            RuleAuditEntry(
                rule: Rule(
                    id: "safe_rule",
                    name: "Safe Rule",
                    description: "A safe rule",
                    category: .lint,
                    isOptIn: false,
                    supportsAutocorrection: true
                ),
                impactResult: RuleImpactResult(
                    ruleId: "safe_rule",
                    violationCount: 0,
                    violations: [],
                    affectedFiles: [],
                    simulationDuration: 0.1
                ),
                isCurrentlyEnabled: false
            ),
            RuleAuditEntry(
                rule: Rule(
                    id: "low_rule",
                    name: "Low Rule",
                    description: "A low effort rule",
                    category: .style,
                    isOptIn: false,
                    supportsAutocorrection: false
                ),
                impactResult: RuleImpactResult(
                    ruleId: "low_rule",
                    violationCount: 3,
                    violations: [],
                    affectedFiles: ["file1.swift"],
                    simulationDuration: 0.2
                ),
                isCurrentlyEnabled: false
            ),
            RuleAuditEntry(
                rule: Rule(
                    id: "enabled_rule",
                    name: "Enabled Rule",
                    description: "Already enabled",
                    category: .metrics,
                    isOptIn: false
                ),
                impactResult: nil,
                isCurrentlyEnabled: true
            )
        ]

        let container = DependencyContainer.createForTesting()
        let view = RuleAuditView(
            auditEntries: entries,
            totalSwiftFiles: 42,
            auditDuration: 4.2
        )
        .environment(\.dependencies, container)

        await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
        }
        defer { Task { @MainActor in ViewHosting.expel() } }

        // Check for summary card text
        let hasSafeCard = await UIAsyncTestHelpers.waitForText(
            in: view,
            text: "SAFE TO ENABLE",
            timeout: 3.0
        )
        let hasLowCard = await UIAsyncTestHelpers.waitForText(
            in: view,
            text: "LOW EFFORT",
            timeout: 3.0
        )

        // Check for rule names
        let hasSafeRule = await UIAsyncTestHelpers.waitForText(
            in: view,
            text: "safe_rule",
            timeout: 3.0
        )
        let hasLowRule = await UIAsyncTestHelpers.waitForText(
            in: view,
            text: "low_rule",
            timeout: 3.0
        )
        let hasEnabledRule = await UIAsyncTestHelpers.waitForText(
            in: view,
            text: "enabled_rule",
            timeout: 3.0
        )

        // Check status bar content
        let hasStatusBar = await UIAsyncTestHelpers.waitForText(
            in: view,
            text: "3 rules tested against 42 Swift files",
            timeout: 3.0
        )

        #expect(hasSafeCard)
        #expect(hasLowCard)
        #expect(hasSafeRule)
        #expect(hasLowRule)
        #expect(hasEnabledRule)
        #expect(hasStatusBar)
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

    override func simulateRules(
        ruleIds: [String],
        workspace: Workspace,
        baseConfigPath: URL?,
        optInRuleIds: Set<String> = [],
        progressHandler: ((Int, Int, String) -> Void)? = nil
    ) async throws -> BatchSimulationResult {
        await Task.yield()
        var ruleResults: [RuleImpactResult] = []
        for (index, ruleId) in ruleIds.enumerated() {
            progressHandler?(index + 1, ruleIds.count, ruleId)
            let result = results[ruleId] ?? RuleImpactResult(
                ruleId: ruleId,
                violationCount: 0,
                violations: [],
                affectedFiles: [],
                simulationDuration: 0.1
            )
            ruleResults.append(result)
        }
        return BatchSimulationResult(
            results: ruleResults,
            totalDuration: 1.0,
            completedAt: Date.now
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
