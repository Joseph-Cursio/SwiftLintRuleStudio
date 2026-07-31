//
//  RuleAuditPipelineTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for the audit run itself: partitioning rules by configured state and
//  driving an injected simulator.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

/// Records what the audit asks of the simulator, and can fail on demand.
final class RecordingImpactSimulator: ImpactSimulatorProtocol {
    struct Call {
        let ruleIds: [String]
        let classification: RuleClassification
        let baseConfigPath: URL?
    }

    private(set) var simulateRulesCalls: [Call] = []
    private let results: [String: RuleImpactResult]
    private let totalDuration: TimeInterval
    private let failure: Error?

    init(
        results: [String: RuleImpactResult] = [:],
        totalDuration: TimeInterval = 2.5,
        failure: Error? = nil
    ) {
        self.results = results
        self.totalDuration = totalDuration
        self.failure = failure
    }

    func simulateRules(
        ruleIds: [String],
        workspace _: Workspace,
        baseConfigPath: URL?,
        classification: RuleClassification,
        progressHandler: ((Int, Int, String) -> Void)?
    ) async throws -> BatchSimulationResult {
        await Task.yield()
        simulateRulesCalls.append(
            Call(ruleIds: ruleIds, classification: classification, baseConfigPath: baseConfigPath)
        )
        if let failure {
            throw failure
        }
        var ruleResults: [RuleImpactResult] = []
        for (index, ruleId) in ruleIds.enumerated() {
            progressHandler?(index + 1, ruleIds.count, ruleId)
            ruleResults.append(
                results[ruleId] ?? RuleImpactResult(
                    ruleId: ruleId,
                    violationCount: 0,
                    violations: [],
                    affectedFiles: [],
                    simulationDuration: 0.1
                )
            )
        }
        return BatchSimulationResult(
            results: ruleResults,
            totalDuration: totalDuration,
            completedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func simulateRule(
        ruleId: String,
        workspace _: Workspace,
        baseConfigPath _: URL?,
        options _: RuleSimulationOptions
    ) async throws -> RuleImpactResult {
        await Task.yield()
        return results[ruleId] ?? RuleImpactResult(
            ruleId: ruleId,
            violationCount: 0,
            violations: [],
            affectedFiles: [],
            simulationDuration: 0
        )
    }

    func findSafeRules(
        workspace _: Workspace,
        baseConfigPath _: URL?,
        disabledRuleIds: [String],
        classification _: RuleClassification,
        progressHandler _: ((Int, Int, String) -> Void)?
    ) async throws -> [String] {
        await Task.yield()
        return disabledRuleIds
    }
}

struct SimulationFailure: Error {}

@MainActor
@Suite("RuleAuditView audit pipeline")
struct RuleAuditPipelineTests {

    // MARK: - Fixtures

    private static func makeRule(
        _ identifier: String,
        isOptIn: Bool = false,
        isAnalyzer: Bool = false
    ) -> Rule {
        Rule(
            id: identifier,
            name: identifier,
            description: "desc for \(identifier)",
            category: .lint,
            isOptIn: isOptIn,
            isAnalyzer: isAnalyzer
        )
    }

    /// A workspace with a `.swiftlint.yml` containing `configContents`. The
    /// default is an empty rule list rather than an empty file, because the
    /// engine rejects a zero-byte document as unparseable.
    private static func makeWorkspace(
        configContents: String = "disabled_rules: []\n"
    ) throws -> Workspace {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuleAuditPipelineTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try configContents.write(
            to: root.appendingPathComponent(".swiftlint.yml"),
            atomically: true,
            encoding: .utf8
        )
        return Workspace(path: root)
    }

    private static func makeWorkspace(disabling ruleId: String) throws -> Workspace {
        try makeWorkspace(configContents: "disabled_rules:\n  - \(ruleId)\n")
    }

    // MARK: - partitionRules

    @Test("Rules split by whether the configuration switches them on")
    func partitionsRulesByConfiguredState() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["turned_off"]
        config.optInRules = ["opted_in"]

        let rules = [
            Self.makeRule("on_by_default"),
            Self.makeRule("turned_off"),
            Self.makeRule("opted_in", isOptIn: true),
            Self.makeRule("not_opted_in", isOptIn: true)
        ]

        let (enabled, disabled) = RuleAuditView.partitionRules(rules, config: config)

        #expect(Set(enabled.map(\.id)) == ["on_by_default", "opted_in"])
        #expect(Set(disabled.map(\.id)) == ["turned_off", "not_opted_in"])
    }

    @Test("Partitioning keeps every rule in exactly one side")
    func partitionIsTotalAndDisjoint() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["b_rule"]
        let rules = ["a_rule", "b_rule", "c_rule"].map { Self.makeRule($0) }

        let (enabled, disabled) = RuleAuditView.partitionRules(rules, config: config)

        #expect(enabled.count + disabled.count == rules.count)
        #expect(Set(enabled.map(\.id)).isDisjoint(with: Set(disabled.map(\.id))))
    }

    @Test("Partitioning an empty rule list yields two empty sides")
    func partitionsEmptyRuleList() {
        let (enabled, disabled) = RuleAuditView.partitionRules(
            [],
            config: YAMLConfigurationEngine.YAMLConfig()
        )

        #expect(enabled.isEmpty)
        #expect(disabled.isEmpty)
    }

    // MARK: - performAudit

    @Test("Only the disabled rules are handed to the simulator")
    func auditSimulatesOnlyDisabledRules() async throws {
        let workspace = try Self.makeWorkspace(disabling: "off_rule")
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        let simulator = RecordingImpactSimulator()
        let rules = [Self.makeRule("on_rule"), Self.makeRule("off_rule")]

        _ = try await RuleAuditView.performAudit(
            workspace: workspace,
            rules: rules,
            simulator: simulator
        ) { _ in }

        #expect(simulator.simulateRulesCalls.count == 1)
        #expect(simulator.simulateRulesCalls[0].ruleIds == ["off_rule"])
    }

    @Test("With nothing disabled the simulator is never invoked")
    func auditSkipsSimulatorWhenNothingDisabled() async throws {
        let workspace = try Self.makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        let simulator = RecordingImpactSimulator()

        let outcome = try await RuleAuditView.performAudit(
            workspace: workspace,
            rules: [Self.makeRule("on_rule")],
            simulator: simulator
        ) { _ in }

        #expect(simulator.simulateRulesCalls.isEmpty)
        #expect(outcome.duration == 0)
        #expect(outcome.entries.count == 1)
        #expect(outcome.entries[0].isCurrentlyEnabled)
    }

    @Test("The simulator receives the classification and the base config path")
    func auditForwardsClassificationAndConfigPath() async throws {
        let workspace = try Self.makeWorkspace(disabling: "plain_off")
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        let simulator = RecordingImpactSimulator()
        let rules = [
            Self.makeRule("plain_off"),
            Self.makeRule("opted_in", isOptIn: true),
            Self.makeRule("analyzed", isAnalyzer: true)
        ]

        _ = try await RuleAuditView.performAudit(
            workspace: workspace,
            rules: rules,
            simulator: simulator
        ) { _ in }

        let call = try #require(simulator.simulateRulesCalls.first)
        #expect(call.classification.optInRuleIds == ["opted_in"])
        #expect(call.classification.analyzerRuleIds == ["analyzed"])
        #expect(call.baseConfigPath == workspace.configPath)
    }

    @Test("Progress is reported once per simulated rule")
    func auditReportsProgress() async throws {
        let workspace = try Self.makeWorkspace(
            configContents: "disabled_rules:\n  - first_off\n  - second_off\n"
        )
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        let simulator = RecordingImpactSimulator()
        let rules = [Self.makeRule("first_off"), Self.makeRule("second_off")]

        nonisolated(unsafe) var progress: [AuditProgress] = []
        _ = try await RuleAuditView.performAudit(
            workspace: workspace,
            rules: rules,
            simulator: simulator
        ) { progress.append($0) }

        #expect(progress.count == 2)
        #expect(progress.map(\.current) == [1, 2])
        #expect(progress.allSatisfy { $0.total == 2 })
        #expect(Set(progress.map(\.ruleId)) == ["first_off", "second_off"])
    }

    @Test("The outcome carries the simulated results, file count and duration")
    func auditReportsOutcome() async throws {
        let workspace = try Self.makeWorkspace(disabling: "off_rule")
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        try "struct A {}".write(
            to: workspace.path.appendingPathComponent("A.swift"),
            atomically: true,
            encoding: .utf8
        )

        let simulator = RecordingImpactSimulator(
            results: [
                "off_rule": RuleImpactResult(
                    ruleId: "off_rule",
                    violationCount: 6,
                    violations: [],
                    affectedFiles: ["A.swift"],
                    simulationDuration: 0.2
                )
            ],
            totalDuration: 4.0
        )

        let outcome = try await RuleAuditView.performAudit(
            workspace: workspace,
            rules: [Self.makeRule("off_rule")],
            simulator: simulator
        ) { _ in }

        #expect(outcome.duration == 4.0)
        #expect(outcome.swiftFileCount == 1)
        #expect(outcome.entries.count == 1)
        #expect(outcome.entries[0].violationCount == 6)
    }

    @Test("A failing simulator propagates its error to the caller")
    func auditPropagatesSimulatorFailure() async throws {
        let workspace = try Self.makeWorkspace(disabling: "off_rule")
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        let simulator = RecordingImpactSimulator(failure: SimulationFailure())

        await #expect(throws: SimulationFailure.self) {
            _ = try await RuleAuditView.performAudit(
                workspace: workspace,
                rules: [Self.makeRule("off_rule")],
                simulator: simulator
            ) { _ in }
        }
    }
}
