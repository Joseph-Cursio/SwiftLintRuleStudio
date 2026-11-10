//
//  RuleAuditViewTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for RuleAuditView
//

import SwiftLintCLIBackend
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import SwiftUI
import Testing
import ViewInspector

final class MockImpactSimulator: ImpactSimulatorProtocol {
    private let safeRuleIds: [String]
    private let results: [String: RuleImpactResult]
    private(set) var findSafeRulesCalls = 0
    private(set) var simulateRuleCalls = 0

    init(safeRuleIds: [String], results: [String: RuleImpactResult]) {
        self.safeRuleIds = safeRuleIds
        self.results = results
    }

    func findSafeRules(
        workspace _: Workspace,
        baseConfigPath _: URL?,
        disabledRuleIds _: [String],
        classification _: RuleClassification,
        progressHandler: ((Int, Int, String) -> Void)?
    ) async throws -> [String] {
        await Task.yield()
        findSafeRulesCalls += 1
        for (index, ruleId) in safeRuleIds.enumerated() {
            progressHandler?(index + 1, safeRuleIds.count, ruleId)
        }
        return safeRuleIds
    }

    func simulateRule(
        ruleId: String,
        workspace _: Workspace,
        baseConfigPath _: URL?,
        options _: RuleSimulationOptions
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

    func simulateRules(
        ruleIds: [String],
        workspace _: Workspace,
        baseConfigPath _: URL?,
        classification _: RuleClassification,
        progressHandler: ((Int, Int, String) -> Void)?
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
        let tempDir = try Self.makeAuditWorkspace()
        let rules = [
            Self.disabledRule(id: "safe_rule_1", name: "Safe Rule 1"),
            Self.disabledRule(id: "safe_rule_2", name: "Safe Rule 2"),
        ]
        let results = [
            "safe_rule_1": Self.cleanResult(ruleId: "safe_rule_1"),
            "safe_rule_2": Self.cleanResult(ruleId: "safe_rule_2"),
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
        let entries = Self.sampleEntries()

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

        // Summary cards, rule names and the status bar
        let hasSafeCard = await Self.waitForText("SAFE TO ENABLE", in: view)
        let hasLowCard = await Self.waitForText("LOW EFFORT", in: view)
        let hasSafeRule = await Self.waitForText("safe_rule", in: view)
        let hasLowRule = await Self.waitForText("low_rule", in: view)
        let hasEnabledRule = await Self.waitForText("enabled_rule", in: view)
        let hasStatusBar = await Self.waitForText("3 rules tested against 42 Swift files", in: view)

        #expect(hasSafeCard)
        #expect(hasLowCard)
        #expect(hasSafeRule)
        #expect(hasLowRule)
        #expect(hasEnabledRule)
        #expect(hasStatusBar)
    }
}
