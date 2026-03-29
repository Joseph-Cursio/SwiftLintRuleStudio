//
//  SafeRulesDiscoveryViewAdditionalTests.swift
//  SwiftLintRuleStudioTests
//
//  Additional tests for SafeRulesDiscoveryView (split from SafeRulesDiscoveryViewTests)
//

import Testing
import SwiftUI
import ViewInspector
@testable import SwiftLintRuleStudioCore
@testable import SwiftLintRuleStudio

@MainActor
struct SafeRulesDiscoveryViewAdditionalTests {

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

        let toggleCount = try await MainActor.run {
            let row = SafeRuleRow(ruleResult: ruleResult, isSelected: false) {
                tracker.toggleCount += 1
            }
            ViewHosting.expel()
            ViewHosting.host(view: row)
            defer { ViewHosting.expel() }
            let inspector = try row.inspect()
            // SafeRuleRow.body is: Button(action: onToggle) { HStack { Button {...} ... } }
            // Inner checkbox button (index 0 in HStack):
            try inspector.button().labelView().hStack().button(0).tap()
            // Outer row button:
            try inspector.button().tap()
            return tracker.toggleCount
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

        #expect(rule1Enabled)
        #expect(rule2Enabled)
        #expect(disabledEmpty)
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
            completedAt: Date.now
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
        #expect(allSafe)
        #expect(allHaveViolations)
    }

    @Test("BatchSimulationResult handles empty results")
    func testBatchSimulationResultEmpty() async throws {
        let batchResult = BatchSimulationResult(
            results: [],
            totalDuration: 0.0,
            completedAt: Date.now
        )

        // Extract values to avoid Swift 6 false positives
        // BatchSimulationResult is a struct (Sendable), but Swift 6 has false positives
        let (safeRulesEmpty, violationsEmpty) = await MainActor.run {
            (batchResult.safeRules.isEmpty, batchResult.rulesWithViolations.isEmpty)
        }
        #expect(safeRulesEmpty)
        #expect(violationsEmpty)
    }
}
