//
//  SafeRulesDiscoveryViewTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for SafeRulesDiscoveryView
//

import Testing
import SwiftUI
import ViewInspector
@testable import SwiftLIntRuleStudio

// swiftlint:disable function_body_length file_length

// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
// swiftlint:disable:next type_body_length
struct SafeRulesDiscoveryViewTests {
    
    // Workaround type to bypass Sendable check for SwiftUI views
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
            .environmentObject(container)
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
        let swiftLintCLI = SwiftLintCLI(cacheManager: cacheManager)
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
            .environmentObject(container)

        return ViewResult(view: view, container: container)
    }
    
    @Test("SafeRulesDiscoveryView initializes correctly")
    func testInitialization() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createSafeRulesDiscoveryView() }.value
        let view = result.view
        let container = result.container
        
        // Verify view can be created
        let hasImpactSimulator = await MainActor.run {
            container.impactSimulator != nil
        }
        #expect(hasImpactSimulator == true)
    }
    
    @Test("SafeRulesDiscoveryView shows empty state")
    func testEmptyStateView() async throws {
        let result = await Task { @MainActor in createSafeRulesDiscoveryView() }.value
        let view = result.view
        
        nonisolated(unsafe) let viewCapture = view
        let (hasHeader, hasEmptyTitle, hasEmptySubtitle) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
            defer { ViewHosting.expel() }
            let inspector = try viewCapture.inspect()
            let hasHeader = (try? inspector.find(text: "Discover Safe Rules")) != nil
            let hasEmptyTitle = (try? inspector.find(text: "No Safe Rules Discovered")) != nil
            let emptySubtitle = "Click 'Discover Safe Rules' to analyze disabled rules in your workspace"
            let hasEmptySubtitle = (try? inspector.find(text: emptySubtitle)) != nil
            return (hasHeader, hasEmptyTitle, hasEmptySubtitle)
        }
        
        #expect(hasHeader == true)
        #expect(hasEmptyTitle == true)
        #expect(hasEmptySubtitle == true)
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

        let view = result.view
        let container = result.container
        let hasWorkspace = await MainActor.run { container.workspaceManager.currentWorkspace != nil }
        let ruleCount = await MainActor.run { container.ruleRegistry.rules.count }
        #expect(hasWorkspace == true)
        #expect(ruleCount == 2)
        nonisolated(unsafe) let viewCapture = view
        await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
        }
        defer { Task { @MainActor in ViewHosting.expel() } }

        let didTapDiscover = try await MainActor.run {
            let inspector = try viewCapture.inspect()
            let buttons = try inspector.findAll(ViewType.Button.self)
            let discoverButton = buttons.first { button in
                let text = try? button.labelView().find(ViewType.Text.self).string()
                return text == "Discover Safe Rules"
            }
            guard let discoverButton = discoverButton else {
                return false
            }
            try discoverButton.tap()
            return true
        }
        #expect(didTapDiscover == true)

        let didComplete = await UIAsyncTestHelpers.waitForConditionAsync(timeout: 4.0) {
            let (findCalls, simulateCalls) = await MainActor.run {
                let mock = container.impactSimulator as? MockImpactSimulator
                return (mock?.findSafeRulesCalls ?? 0, mock?.simulateRuleCalls ?? 0)
            }
            return findCalls >= 1 && simulateCalls >= 2
        }
        let (findCalls, simulateCalls) = await MainActor.run {
            let mock = container.impactSimulator as? MockImpactSimulator
            return (mock?.findSafeRulesCalls ?? 0, mock?.simulateRuleCalls ?? 0)
        }
        #expect(didComplete == true)
        #expect(findCalls == 1)
        #expect(simulateCalls == 2)

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
        .environmentObject(container)

        nonisolated(unsafe) let viewCapture = view
        await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: viewCapture)
        }
        defer { Task { @MainActor in ViewHosting.expel() } }

        let hasSummary = await UIAsyncTestHelpers.waitForText(
            in: viewCapture,
            text: "Found 2 safe rules",
            timeout: 3.0
        )
        let hasSelectAll = await UIAsyncTestHelpers.waitForText(
            in: viewCapture,
            text: "Select All",
            timeout: 3.0
        )
        let hasDeselectAll = await UIAsyncTestHelpers.waitForText(
            in: viewCapture,
            text: "Deselect All",
            timeout: 3.0
        )
        let hasRule1 = await UIAsyncTestHelpers.waitForText(
            in: viewCapture,
            text: "safe_rule_1",
            timeout: 3.0
        )
        let hasRule2 = await UIAsyncTestHelpers.waitForText(
            in: viewCapture,
            text: "safe_rule_2",
            timeout: 3.0
        )

        #expect(hasSummary == true)
        #expect(hasSelectAll == true)
        #expect(hasDeselectAll == true)
        #expect(hasRule1 == true)
        #expect(hasRule2 == true)
    }
    
    @Test("SafeRuleRow toggle fires for button and row tap")
    func testSafeRuleRowToggle() async throws {
        let ruleResult = RuleImpactResult(
            ruleId: "safe_rule",
            violationCount: 0,
            violations: [],
            affectedFiles: [],
            simulationDuration: 0.3
        )
        
        @MainActor
        class ToggleTracker {
            var toggleCount = 0
        }
        
        let tracker = await MainActor.run { ToggleTracker() }
        nonisolated(unsafe) let trackerCapture = tracker
        
        let toggleCount = try await MainActor.run {
            let row = SafeRuleRow(ruleResult: ruleResult, isSelected: false) {
                trackerCapture.toggleCount += 1
            }
            nonisolated(unsafe) let rowCapture = row
            ViewHosting.expel()
            ViewHosting.host(view: rowCapture)
            defer { ViewHosting.expel() }
            let inspector = try rowCapture.inspect()
            try inspector.hStack().button(0).tap()
            try inspector.hStack().callOnTapGesture()
            return trackerCapture.toggleCount
        }
        
        #expect(toggleCount == 2)
    }

    @Test("SafeRulesDiscoveryView applyEnableRules updates config")
    func testApplyEnableRules() async throws {
        let configPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("SafeRulesDiscoveryViewTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(".swiftlint.yml")
        
        let (rule1Enabled, rule2Enabled, disabledEmpty) = await MainActor.run {
            let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
            var config = yamlEngine.getConfig()
            config.disabledRules = ["rule_1", "rule_2"]
            config.rules["rule_1"] = RuleConfiguration(enabled: false)
            
            SafeRulesDiscoveryView.applyEnableRules(
                config: &config,
                ruleIds: ["rule_1", "rule_2"],
                optInRuleIds: []
            )
            
            let rule1Enabled = config.rules["rule_1"]?.enabled == true
            let rule2Enabled = config.rules["rule_2"]?.enabled == true
            let disabledEmpty = config.disabledRules == nil || config.disabledRules?.isEmpty == true
            return (rule1Enabled, rule2Enabled, disabledEmpty)
        }
        
        #expect(rule1Enabled == true)
        #expect(rule2Enabled == true)
        #expect(disabledEmpty == true)
    }
    
    @Test("BatchSimulationResult correctly categorizes rules")
    func testBatchSimulationResultCategorization() async throws {
        let results = [
            RuleImpactResult(
                ruleId: "safe_rule_1",
                violationCount: 0,
                violations: [],
                affectedFiles: [],
                simulationDuration: 1.0
            ),
            RuleImpactResult(
                ruleId: "safe_rule_2",
                violationCount: 0,
                violations: [],
                affectedFiles: [],
                simulationDuration: 1.0
            ),
            RuleImpactResult(
                ruleId: "unsafe_rule",
                violationCount: 5,
                violations: [],
                affectedFiles: ["file.swift"],
                simulationDuration: 1.0
            )
        ]
        
        let batchResult = BatchSimulationResult(
            results: results,
            totalDuration: 3.0,
            completedAt: Date()
        )
        
        // Extract values to avoid Swift 6 false positives
        // BatchSimulationResult is a struct (Sendable), but Swift 6 has false positives
        let (safeRulesCount, violationsCount, allSafe, allHaveViolations) = await MainActor.run {
            let safeRules = batchResult.safeRules
            let rulesWithViolations = batchResult.rulesWithViolations
            return (
                safeRules.count,
                rulesWithViolations.count,
                safeRules.allSatisfy { $0.isSafe },
                rulesWithViolations.allSatisfy { $0.hasViolations }
            )
        }
        #expect(safeRulesCount == 2)
        #expect(violationsCount == 1)
        #expect(allSafe == true)
        #expect(allHaveViolations == true)
    }
    
    @Test("BatchSimulationResult handles empty results")
    func testBatchSimulationResultEmpty() async throws {
        let batchResult = BatchSimulationResult(
            results: [],
            totalDuration: 0.0,
            completedAt: Date()
        )
        
        // Extract values to avoid Swift 6 false positives
        // BatchSimulationResult is a struct (Sendable), but Swift 6 has false positives
        let (safeRulesEmpty, violationsEmpty) = await MainActor.run {
            (batchResult.safeRules.isEmpty, batchResult.rulesWithViolations.isEmpty)
        }
        #expect(safeRulesEmpty == true)
        #expect(violationsEmpty == true)
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

private struct StubSwiftLintCLI: SwiftLintCLIProtocol {
    func detectSwiftLintPath() throws -> URL { throw SwiftLintError.notFound }
    func executeRulesCommand() throws -> Data { Data() }
    func executeRuleDetailCommand(ruleId: String) throws -> Data { Data() }
    func generateDocsForRule(ruleId: String) throws -> String { "" }
    func executeLintCommand(configPath: URL?, workspacePath: URL) throws -> Data { Data() }
    func getVersion() throws -> String { "0.0.0" }
}
// swiftlint:enable function_body_length file_length