//
//  RuleAuditUnmeasuredPipelineTests.swift
//  SwiftLintRuleStudioTests
//
//  The audit run for rules it can't measure: the simulator is told which SourceKit rules
//  this edition can't lint, and whatever it couldn't measure reaches the audit as not safe.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
@Suite("RuleAuditView audit pipeline: rules with no violation count")
struct RuleAuditUnmeasuredPipelineTests {

    // MARK: - Fixtures

    private static func makeRule(_ identifier: String, usesSourceKit: Bool = false) -> Rule {
        Rule(
            id: identifier,
            name: identifier,
            description: "desc for \(identifier)",
            category: .lint,
            isOptIn: false,
            usesSourceKit: usesSourceKit
        )
    }

    /// A workspace whose `.swiftlint.yml` disables `ruleIds`.
    private static func makeWorkspace(disabling ruleIds: [String]) throws -> Workspace {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuleAuditUnmeasuredPipelineTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = "disabled_rules:\n" + ruleIds.map { "  - \($0)\n" }.joined()
        try config.write(to: root.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        return Workspace(path: root)
    }

    // MARK: - SourceKit rules

    @Test("Without SourceKit, the audit tells the simulator which SourceKit rules it can't lint")
    func auditClassifiesSourceKitRulesWithoutSourceKit() async throws {
        // The sandboxed edition can't load SourceKit, so linting such a rule reports 0 —
        // which would show it as safe to enable. The simulator reports it as unmeasurable
        // instead (covered in Core's ImpactSimulatorSourceKitTests), given this set.
        let workspace = try Self.makeWorkspace(disabling: ["plain_off", "sourcekit_off"])
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        let simulator = RecordingImpactSimulator()
        let rules = [Self.makeRule("plain_off"), Self.makeRule("sourcekit_off", usesSourceKit: true)]

        _ = try await RuleAuditView.performAudit(
            workspace: workspace,
            rules: rules,
            simulator: simulator,
            capabilities: []
        ) { _ in }

        let call = try #require(simulator.simulateRulesCalls.first)
        #expect(Set(call.ruleIds) == ["plain_off", "sourcekit_off"])
        #expect(call.classification.sourceKitUnavailableRuleIds == ["sourcekit_off"])
    }

    @Test("With SourceKit, no rule is classified as unlintable")
    func auditClassifiesNothingWithSourceKit() async throws {
        let workspace = try Self.makeWorkspace(disabling: ["sourcekit_off"])
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        let simulator = RecordingImpactSimulator()

        _ = try await RuleAuditView.performAudit(
            workspace: workspace,
            rules: [Self.makeRule("sourcekit_off", usesSourceKit: true)],
            simulator: simulator,
            capabilities: Set(AppCapability.allCases)
        ) { _ in }

        let call = try #require(simulator.simulateRulesCalls.first)
        #expect(call.classification.sourceKitUnavailableRuleIds.isEmpty)
    }

    @Test("A SourceKit rule the simulator reports unmeasurable is not safe")
    func auditKeepsUnlintableSourceKitRulesOutOfSafe() async throws {
        let workspace = try Self.makeWorkspace(disabling: ["plain_off", "sourcekit_off"])
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        let simulator = RecordingImpactSimulator(
            results: ["sourcekit_off": .unmeasurable(ruleId: "sourcekit_off", reason: .sourceKitUnavailable)]
        )
        let rules = [Self.makeRule("plain_off"), Self.makeRule("sourcekit_off", usesSourceKit: true)]

        let outcome = try await RuleAuditView.performAudit(
            workspace: workspace,
            rules: rules,
            simulator: simulator,
            capabilities: []
        ) { _ in }

        let sourceKitEntry = try #require(outcome.entries.first { $0.id == "sourcekit_off" })
        #expect(sourceKitEntry.effortCategory == .unmeasurable)
        #expect(RuleAuditView.safeDisabledRuleIds(in: outcome.entries) == ["plain_off"])
    }

    // MARK: - Simulator results

    @Test("A rule the simulator couldn't measure reaches the audit as not safe")
    func auditKeepsSimulatorFailuresOutOfSafe() async throws {
        let workspace = try Self.makeWorkspace(disabling: ["broken", "analyzed", "clean"])
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        let simulator = RecordingImpactSimulator(
            results: [
                "broken": .failed(ruleId: "broken", reason: "Invalid configuration"),
                "analyzed": .unmeasurable(ruleId: "analyzed", reason: .analyzerRule)
            ]
        )
        let rules = [Self.makeRule("broken"), Self.makeRule("analyzed"), Self.makeRule("clean")]

        let outcome = try await RuleAuditView.performAudit(
            workspace: workspace,
            rules: rules,
            simulator: simulator,
            capabilities: Set(AppCapability.allCases)
        ) { _ in }

        #expect(RuleAuditView.safeDisabledRuleIds(in: outcome.entries) == ["clean"])
        #expect(outcome.entries.first?.id == "clean", "an unmeasured rule must not sort in among the safe ones")
    }
}
