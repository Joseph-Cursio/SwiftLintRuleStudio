//
//  ImpactSimulatorRoutingTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for analyzer / opt-in routing in ImpactSimulator's temp config. Analyzer
//  rules are never linted, so their routing is checked on ConfigRuleEnabler.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct ImpactSimulatorRoutingTests {

    /// Loads the mirror's root YAML config the simulator wrote before its
    /// defer-cleanup removes it, and stashes the parsed YAMLConfig for assertions.
    private actor LoadedConfigStore {
        private(set) var configs: [YAMLConfigurationEngine.YAMLConfig] = []

        func record(_ config: YAMLConfigurationEngine.YAMLConfig) {
            configs.append(config)
        }
    }

    /// Wire a mock CLI that loads the mirror's root config from disk inside the
    /// lint handler (before the simulator's defer cleanup runs) and stores it.
    ///
    /// The simulator now lints a shadow *workspace* rather than a lone `--config`
    /// file: it passes `configPath: nil` and hands the mirror root as the
    /// workspace path, with the rule-enabled config at `<root>/.swiftlint.yml`.
    private static func makeConfigSnapshotCLI() async -> (MockSwiftLintCLIActor, LoadedConfigStore) {
        let store = LoadedConfigStore()
        let mockCLI = MockSwiftLintCLIActor()
        await mockCLI.setLintCommandHandler { @Sendable _, workspacePath in
            let rootConfigPath = workspacePath.appendingPathComponent(".swiftlint.yml")
            let captured = await MainActor.run { () -> YAMLConfigurationEngine.YAMLConfig? in
                let engine = YAMLConfigurationEngine(configPath: rootConfigPath)
                do {
                    try engine.load()
                    return engine.getConfig()
                } catch {
                    return nil
                }
            }
            if let captured = captured {
                await store.record(captured)
            }
            return Data("[]".utf8)
        }
        return (mockCLI, store)
    }

    @Test("simulateRule reports an analyzer rule as unmeasurable without linting it")
    func analyzerRuleIsNotLintedForSingleRule() async throws {
        // `swiftlint lint` never runs analyzer rules, so a lint would report 0 — which the
        // app reads as "safe to enable". The simulator must say it can't measure the rule.
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        _ = try ImpactSimulatorTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let value = 1\n"
        )

        let workspace = Workspace(path: tempDir)
        let (mockCLI, store) = await Self.makeConfigSnapshotCLI()

        let result = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "unused_declaration",
                workspace: workspace,
                baseConfigPath: nil,
                options: RuleSimulationOptions(isOptIn: false, isAnalyzer: true)
            )
        }

        #expect(await store.configs.isEmpty, "an analyzer rule must not cost a lint")
        #expect(result.measurement == .unmeasurable(.analyzerRule))
        #expect(result.isSafe == false)
        #expect(result.violationCount == -1)
    }

    @Test("An enabled analyzer rule goes in analyzer_rules, not opt_in_rules")
    func analyzerRuleRoutingInConfig() {
        // The simulator no longer lints analyzer rules, so this is checked on the YAML
        // mutation directly rather than through a simulation.
        var config = YAMLConfigurationEngine.YAMLConfig()

        ConfigRuleEnabler.enableRule("unused_declaration", in: &config, isOptIn: false, isAnalyzer: true)

        #expect(config.analyzerRules?.contains("unused_declaration") == true)
        #expect(config.optInRules?.contains("unused_declaration") != true)
    }

    @Test("simulateRule routes opt-in rules into opt_in_rules, not analyzer_rules")
    func optInRuleRoutingForSingleRule() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        _ = try ImpactSimulatorTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let value = 1\n"
        )

        let workspace = Workspace(path: tempDir)
        let (mockCLI, store) = await Self.makeConfigSnapshotCLI()

        _ = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "explicit_init",
                workspace: workspace,
                baseConfigPath: nil,
                options: RuleSimulationOptions(isOptIn: true, isAnalyzer: false)
            )
        }

        let configs = await store.configs
        let captured = try #require(configs.first)
        #expect(captured.optInRules?.contains("explicit_init") == true)
        #expect(captured.analyzerRules?.contains("explicit_init") != true)
    }

    @Test("simulateRule with default flags writes neither analyzer nor opt-in list")
    func defaultRuleNoSpecialList() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        _ = try ImpactSimulatorTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let value = 1\n"
        )

        let workspace = Workspace(path: tempDir)
        let (mockCLI, store) = await Self.makeConfigSnapshotCLI()

        _ = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "force_cast",
                workspace: workspace,
                baseConfigPath: nil
            )
        }

        let configs = await store.configs
        let captured = try #require(configs.first)
        // Plain default-enabled rule belongs in neither special list
        #expect(captured.analyzerRules?.contains("force_cast") != true)
        #expect(captured.optInRules?.contains("force_cast") != true)
        // No disabled_rules entry either — the simulator enables it
        #expect(captured.disabledRules?.contains("force_cast") != true)
    }

    @Test("simulateRules lints opt-in and plain rules but reports analyzer rules unmeasurable")
    func batchSimulationRoutesPerRuleKind() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        _ = try ImpactSimulatorTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let value = 1\n"
        )

        let workspace = Workspace(path: tempDir)
        let (mockCLI, store) = await Self.makeConfigSnapshotCLI()

        let batch = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRules(
                ruleIds: ["unused_declaration", "explicit_init", "force_cast"],
                workspace: workspace,
                baseConfigPath: nil,
                classification: RuleClassification(
                    optInRuleIds: ["explicit_init"],
                    analyzerRuleIds: ["unused_declaration"]
                )
            )
        }

        // One lint per lintable rule; the analyzer rule gets none.
        let configs = await store.configs
        #expect(configs.count == 2)
        #expect(configs.allSatisfy { $0.analyzerRules?.contains("unused_declaration") != true })

        let measurements = Dictionary(uniqueKeysWithValues: batch.results.map { ($0.ruleId, $0.measurement) })
        #expect(measurements["unused_declaration"] == .unmeasurable(.analyzerRule))
        #expect(measurements["explicit_init"] == .measured)
        #expect(measurements["force_cast"] == .measured)
        #expect(batch.safeRules.map(\.ruleId).sorted() == ["explicit_init", "force_cast"])

        // Each simulation writes a fresh temp config. The rules dict gets
        // collapsed during serialization when entries have no severity or
        // parameters, so we identify configs by their opt-in lists.
        let optInConfig = try #require(
            configs.first { $0.optInRules?.contains("explicit_init") == true }
        )
        #expect(optInConfig.analyzerRules?.contains("explicit_init") != true)

        // The plain rule lands in no list — it's the one simulation with
        // opt_in_rules not populated for its rule.
        let plainConfig = try #require(
            configs.first { $0.optInRules?.contains("explicit_init") != true }
        )
        #expect(plainConfig.optInRules?.contains("force_cast") != true)
        #expect(plainConfig.analyzerRules?.contains("force_cast") != true)
    }

    @Test("Relative included paths in base config are preserved verbatim in the mirror")
    func relativeIncludedPathsPreserved() async throws {
        // The mirror reproduces each config at its real relative location, so
        // relative `included` entries (e.g. `Sources`, `Tests`) resolve correctly
        // within the mirror and must be kept exactly as written — no absolutizing
        // (the old orphan-temp-config approach had to rewrite them to absolute
        // workspace paths; the shadow workspace no longer does).
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        let baseConfigPath = tempDir.appendingPathComponent(".swiftlint.yml")
        let baseYAML = """
        included:
          - Sources
          - Tests
        """
        try baseYAML.write(to: baseConfigPath, atomically: true, encoding: .utf8)

        let workspace = Workspace(path: tempDir)
        let (mockCLI, store) = await Self.makeConfigSnapshotCLI()

        _ = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "explicit_type_interface",
                workspace: workspace,
                baseConfigPath: baseConfigPath,
                options: RuleSimulationOptions(isOptIn: true, isAnalyzer: false)
            )
        }

        let configs = await store.configs
        let captured = try #require(configs.first)
        #expect(captured.included == ["Sources", "Tests"])
    }

    @Test("An absolute included path fails the simulation rather than lint the original files")
    func absoluteIncludedPathFails() async throws {
        // In a copy of the workspace an absolute entry still names the original files, under
        // the original — unchanged — configs, so whatever it measured could be short.
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        let baseConfigPath = tempDir.appendingPathComponent(".swiftlint.yml")
        try "included:\n  - /opt/elsewhere/Sources\n".write(to: baseConfigPath, atomically: true, encoding: .utf8)

        let workspace = Workspace(path: tempDir)
        let (mockCLI, store) = await Self.makeConfigSnapshotCLI()

        await #expect(throws: MirrorUnsupportedSetupError.self) {
            _ = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
                try await simulator.simulateRule(
                    ruleId: "force_cast",
                    workspace: workspace,
                    baseConfigPath: baseConfigPath
                )
            }
        }
        #expect(await store.configs.isEmpty, "nothing was linted")
    }

    @Test("Missing included section stays missing in temp config")
    func missingIncludedStaysMissing() async throws {
        // Without this, the simulator could accidentally introduce an included
        // block, narrowing what SwiftLint scans for workspaces that didn't have
        // one in the first place.
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        let baseConfigPath = tempDir.appendingPathComponent(".swiftlint.yml")
        try "opt_in_rules:\n  - explicit_init\n".write(to: baseConfigPath, atomically: true, encoding: .utf8)

        let workspace = Workspace(path: tempDir)
        let (mockCLI, store) = await Self.makeConfigSnapshotCLI()

        _ = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "explicit_init",
                workspace: workspace,
                baseConfigPath: baseConfigPath,
                options: RuleSimulationOptions(isOptIn: true)
            )
        }

        let configs = await store.configs
        let captured = try #require(configs.first)
        #expect(captured.included == nil)
    }

    @Test("Enabling an analyzer rule the config already lists doesn't list it twice")
    func analyzerRuleIsNotDuplicated() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.analyzerRules = ["unused_declaration"]

        ConfigRuleEnabler.enableRule("unused_declaration", in: &config, isOptIn: false, isAnalyzer: true)

        #expect(config.analyzerRules == ["unused_declaration"])
    }
}
