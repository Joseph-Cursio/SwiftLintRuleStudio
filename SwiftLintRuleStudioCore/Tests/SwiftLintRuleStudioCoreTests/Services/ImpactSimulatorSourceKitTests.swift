//
//  ImpactSimulatorSourceKitTests.swift
//  SwiftLintRuleStudioTests
//
//  The sandboxed edition can't load SourceKit, and a SourceKit rule there lints clean
//  whatever the code holds. The simulator must report such a rule as unmeasurable, not as a
//  0 that reads as "safe to enable" — for the single-rule sheet and the audit alike.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct ImpactSimulatorSourceKitTests {

    /// Counts the lints the simulator asks for.
    private actor LintCounter {
        private(set) var lints = 0

        func increment() { lints += 1 }
    }

    private static func makeCountingCLI() async -> (MockSwiftLintCLIActor, LintCounter) {
        let counter = LintCounter()
        let mockCLI = MockSwiftLintCLIActor()
        await mockCLI.setLintCommandHandler { @Sendable _, _ in
            await counter.increment()
            return Data("[]".utf8)
        }
        return (mockCLI, counter)
    }

    private static func makeRule(_ identifier: String, usesSourceKit: Bool, isAnalyzer: Bool = false) -> Rule {
        Rule(
            id: identifier,
            name: identifier,
            description: "desc",
            category: .lint,
            isOptIn: true,
            isAnalyzer: isAnalyzer,
            usesSourceKit: usesSourceKit
        )
    }

    // MARK: - RuleSimulationOptions(rule:capabilities:)

    @Test("Without SourceKit, a SourceKit rule's options say it can't be linted")
    func optionsWithoutSourceKit() {
        let options = RuleSimulationOptions(rule: Self.makeRule("sk_rule", usesSourceKit: true), capabilities: [])

        #expect(options.isSourceKitUnavailable)
        #expect(options.isOptIn)
    }

    @Test("With SourceKit, a SourceKit rule's options let it be linted")
    func optionsWithSourceKit() {
        let options = RuleSimulationOptions(
            rule: Self.makeRule("sk_rule", usesSourceKit: true),
            capabilities: Set(AppCapability.allCases)
        )

        #expect(options.isSourceKitUnavailable == false)
    }

    @Test("A rule that doesn't use SourceKit can be linted in any edition")
    func optionsForPlainRule() {
        let options = RuleSimulationOptions(rule: Self.makeRule("plain_rule", usesSourceKit: false), capabilities: [])

        #expect(options.isSourceKitUnavailable == false)
    }

    // MARK: - Simulation

    @Test("simulateRule reports a SourceKit rule unmeasurable where SourceKit can't load, without linting")
    func singleRuleWithoutSourceKit() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }
        let (mockCLI, counter) = await Self.makeCountingCLI()

        let result = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "sk_rule",
                workspace: Workspace(path: tempDir),
                baseConfigPath: nil,
                options: RuleSimulationOptions(rule: Self.makeRule("sk_rule", usesSourceKit: true), capabilities: [])
            )
        }

        #expect(result.measurement == .unmeasurable(.sourceKitUnavailable))
        #expect(result.isSafe == false)
        #expect(await counter.lints == 0)
    }

    @Test("simulateRule lints a SourceKit rule where SourceKit loads")
    func singleRuleWithSourceKit() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }
        let (mockCLI, counter) = await Self.makeCountingCLI()

        let result = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "sk_rule",
                workspace: Workspace(path: tempDir),
                baseConfigPath: nil,
                options: RuleSimulationOptions(
                    rule: Self.makeRule("sk_rule", usesSourceKit: true),
                    capabilities: Set(AppCapability.allCases)
                )
            )
        }

        #expect(result.measurement == .measured)
        #expect(await counter.lints == 1)
    }

    @Test("simulateRules reports the SourceKit rules it's told can't load as unmeasurable, and lints the rest")
    func batchWithoutSourceKit() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }
        let (mockCLI, counter) = await Self.makeCountingCLI()

        let batch = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRules(
                ruleIds: ["sk_rule", "plain_rule"],
                workspace: Workspace(path: tempDir),
                baseConfigPath: nil,
                classification: RuleClassification(sourceKitUnavailableRuleIds: ["sk_rule"])
            )
        }

        let measurements = Dictionary(uniqueKeysWithValues: batch.results.map { ($0.ruleId, $0.measurement) })
        #expect(measurements["sk_rule"] == .unmeasurable(.sourceKitUnavailable))
        #expect(measurements["plain_rule"] == .measured)
        #expect(batch.safeRules.map(\.ruleId) == ["plain_rule"])
        #expect(await counter.lints == 1)
    }

    @Test("An analyzer rule that also needs SourceKit is reported as an analyzer rule")
    func analyzerReasonComesFirst() async throws {
        // The analyzer reason holds in every edition; SourceKit's only in one.
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }
        let (mockCLI, _) = await Self.makeCountingCLI()

        let result = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "unused_import",
                workspace: Workspace(path: tempDir),
                baseConfigPath: nil,
                options: RuleSimulationOptions(
                    rule: Self.makeRule("unused_import", usesSourceKit: true, isAnalyzer: true),
                    capabilities: []
                )
            )
        }

        #expect(result.measurement == .unmeasurable(.analyzerRule))
    }
}
