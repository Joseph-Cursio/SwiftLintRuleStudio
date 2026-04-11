//
//  RuleAuditViewAdditionalTests.swift
//  SwiftLintRuleStudioTests
//
//  Additional tests for RuleAuditView support types and actions
//

import Testing
import SwiftUI
import ViewInspector
@testable import SwiftLintRuleStudioCore
@testable import SwiftLintRuleStudio

@MainActor
struct RuleAuditViewAdditionalTests {

    @Test("RuleAuditView applyEnableRules updates config")
    func testApplyEnableRules() async throws {
        let configPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuleAuditViewTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(".swiftlint.yml")

        let (rule1Enabled, rule2Enabled, disabledEmpty) = await MainActor.run {
            let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
            var config = yamlEngine.getConfig()
            config.disabledRules = ["rule_1", "rule_2"]
            config.rules["rule_1"] = RuleConfiguration(enabled: false)

            RuleAuditView.applyEnableRules(
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

    @Test("EffortCategory classifies violation counts correctly")
    func testEffortCategoryClassification() {
        #expect(EffortCategory(violationCount: 0) == .safe)
        #expect(EffortCategory(violationCount: 1) == .low)
        #expect(EffortCategory(violationCount: 5) == .low)
        #expect(EffortCategory(violationCount: 6) == .moderate)
        #expect(EffortCategory(violationCount: 25) == .moderate)
        #expect(EffortCategory(violationCount: 26) == .high)
        #expect(EffortCategory(violationCount: 100) == .high)
    }

    @Test("AuditSummary counts categories correctly")
    func testAuditSummaryCounts() {
        let entries = [
            makeEntry(ruleId: "safe1", violationCount: 0, enabled: false),
            makeEntry(ruleId: "safe2", violationCount: 0, enabled: false),
            makeEntry(ruleId: "low1", violationCount: 3, enabled: false),
            makeEntry(ruleId: "mod1", violationCount: 15, enabled: false),
            makeEntry(ruleId: "high1", violationCount: 50, enabled: false),
            makeEntry(ruleId: "enabled1", violationCount: 0, enabled: true)
        ]

        let summary = AuditSummary(entries: entries, totalSwiftFiles: 42, auditDuration: 3.0)

        #expect(summary.safeCount == 2)
        #expect(summary.lowCount == 1)
        #expect(summary.moderateCount == 1)
        #expect(summary.highCount == 1)
        #expect(summary.totalRulesTested == 6)
        #expect(summary.totalSwiftFiles == 42)
    }

    @Test("RuleAuditEntry computes violationsByFile correctly")
    func testViolationsByFile() {
        let violations = [
            Violation(ruleID: "test_rule", filePath: "FileA.swift", line: 1, severity: .warning, message: "msg"),
            Violation(ruleID: "test_rule", filePath: "FileA.swift", line: 5, severity: .warning, message: "msg"),
            Violation(ruleID: "test_rule", filePath: "FileA.swift", line: 10, severity: .warning, message: "msg"),
            Violation(ruleID: "test_rule", filePath: "FileB.swift", line: 1, severity: .warning, message: "msg")
        ]
        let result = RuleImpactResult(
            ruleId: "test_rule",
            violationCount: 4,
            violations: violations,
            affectedFiles: ["FileA.swift", "FileB.swift"],
            simulationDuration: 0.1
        )
        let entry = RuleAuditEntry(
            rule: Rule(id: "test_rule", name: "Test", description: "desc", category: .lint, isOptIn: false),
            impactResult: result,
            isCurrentlyEnabled: false
        )

        let byFile = entry.violationsByFile
        #expect(byFile.count == 2)
        #expect(byFile[0].file == "FileA.swift")
        #expect(byFile[0].count == 3)
        #expect(byFile[1].file == "FileB.swift")
        #expect(byFile[1].count == 1)
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

        let (safeRulesEmpty, violationsEmpty) = await MainActor.run {
            (batchResult.safeRules.isEmpty, batchResult.rulesWithViolations.isEmpty)
        }
        #expect(safeRulesEmpty)
        #expect(violationsEmpty)
    }

    // MARK: - Helpers

    private func makeEntry(ruleId: String, violationCount: Int, enabled: Bool) -> RuleAuditEntry {
        let result = RuleImpactResult(
            ruleId: ruleId,
            violationCount: violationCount,
            violations: [],
            affectedFiles: [],
            simulationDuration: 0.1
        )
        return RuleAuditEntry(
            rule: Rule(
                id: ruleId,
                name: ruleId,
                description: "desc",
                category: .lint,
                isOptIn: false
            ),
            impactResult: enabled ? nil : result,
            isCurrentlyEnabled: enabled
        )
    }
}
