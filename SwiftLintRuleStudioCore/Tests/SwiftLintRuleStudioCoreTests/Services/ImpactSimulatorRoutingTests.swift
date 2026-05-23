//
//  ImpactSimulatorRoutingTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for analyzer / opt-in routing in ImpactSimulator's temp config
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct ImpactSimulatorRoutingTests {

    /// Loads the temp YAML config the simulator wrote before its defer-cleanup
    /// removes it, and stashes the parsed YAMLConfig for assertions.
    private actor LoadedConfigStore {
        private(set) var configs: [YAMLConfigurationEngine.YAMLConfig] = []

        func record(_ config: YAMLConfigurationEngine.YAMLConfig) {
            configs.append(config)
        }
    }

    /// Wire a mock CLI that loads the temp config from disk inside the lint
    /// handler (before the simulator's defer cleanup runs) and stores it.
    private static func makeConfigSnapshotCLI() async -> (MockSwiftLintCLIActor, LoadedConfigStore) {
        let store = LoadedConfigStore()
        let mockCLI = MockSwiftLintCLIActor()
        await mockCLI.setLintCommandHandler { @Sendable configPath, _ in
            if let path = configPath {
                let captured = await MainActor.run { () -> YAMLConfigurationEngine.YAMLConfig? in
                    let engine = YAMLConfigurationEngine(configPath: path)
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
            }
            return Data("[]".utf8)
        }
        return (mockCLI, store)
    }

    @Test("simulateRule routes analyzer rules into analyzer_rules, not opt_in_rules")
    func analyzerRuleRoutingForSingleRule() async throws {
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
                ruleId: "unused_declaration",
                workspace: workspace,
                baseConfigPath: nil,
                isOptIn: false,
                isAnalyzer: true
            )
        }

        let configs = await store.configs
        let captured = try #require(configs.first)
        #expect(captured.analyzerRules?.contains("unused_declaration") == true)
        #expect(captured.optInRules?.contains("unused_declaration") != true)
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
                isOptIn: true,
                isAnalyzer: false
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

    @Test("simulateRules dispatches analyzer vs opt-in via the membership sets")
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

        _ = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRules(
                ruleIds: ["unused_declaration", "explicit_init", "force_cast"],
                workspace: workspace,
                baseConfigPath: nil,
                optInRuleIds: ["explicit_init"],
                analyzerRuleIds: ["unused_declaration"]
            )
        }

        let configs = await store.configs
        #expect(configs.count == 3)

        // Each simulation writes a fresh temp config. The rules dict gets
        // collapsed during serialization when entries have no severity or
        // parameters, so we identify configs by their analyzer / opt-in lists.
        let analyzerConfig = try #require(
            configs.first { $0.analyzerRules?.contains("unused_declaration") == true }
        )
        #expect(analyzerConfig.optInRules?.contains("unused_declaration") != true)

        let optInConfig = try #require(
            configs.first { $0.optInRules?.contains("explicit_init") == true }
        )
        #expect(optInConfig.analyzerRules?.contains("explicit_init") != true)

        // The plain rule lands in no list — it's the one simulation with
        // neither analyzer_rules nor opt_in_rules populated for its rule.
        let plainConfig = try #require(
            configs.first { config in
                config.analyzerRules?.contains("unused_declaration") != true
                    && config.optInRules?.contains("explicit_init") != true
            }
        )
        #expect(plainConfig.optInRules?.contains("force_cast") != true)
        #expect(plainConfig.analyzerRules?.contains("force_cast") != true)
    }

    @Test("Relative included paths in base config are rewritten to absolute workspace paths")
    func relativeIncludedPathsRewrittenToAbsolute() async throws {
        // Regression: when the workspace .swiftlint.yml has relative included
        // entries (e.g. `Sources`, `Tests`), the temp config — written outside
        // the workspace — resolved them against the temp directory and
        // SwiftLint found nothing to lint, so every simulated rule reported
        // zero violations.
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
                isOptIn: true,
                isAnalyzer: false
            )
        }

        let configs = await store.configs
        let captured = try #require(configs.first)
        let included = try #require(captured.included)
        let expectedSources = workspace.path.appendingPathComponent("Sources").path
        let expectedTests = workspace.path.appendingPathComponent("Tests").path
        #expect(included.contains(expectedSources))
        #expect(included.contains(expectedTests))
        #expect(included.allSatisfy { $0.hasPrefix("/") })
    }

    @Test("Absolute included paths in base config are preserved as-is")
    func absoluteIncludedPathsPreserved() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        let baseConfigPath = tempDir.appendingPathComponent(".swiftlint.yml")
        let absolutePath = "/opt/elsewhere/Sources"
        let baseYAML = """
        included:
          - \(absolutePath)
        """
        try baseYAML.write(to: baseConfigPath, atomically: true, encoding: .utf8)

        let workspace = Workspace(path: tempDir)
        let (mockCLI, store) = await Self.makeConfigSnapshotCLI()

        _ = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "force_cast",
                workspace: workspace,
                baseConfigPath: baseConfigPath
            )
        }

        let configs = await store.configs
        let captured = try #require(configs.first)
        #expect(captured.included == [absolutePath])
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
                isOptIn: true
            )
        }

        let configs = await store.configs
        let captured = try #require(configs.first)
        #expect(captured.included == nil)
    }

    @Test("appendUnique does not duplicate analyzer rule already present in base config")
    func appendUniqueIsIdempotent() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        // Base config already lists the analyzer rule.
        let baseConfigPath = tempDir.appendingPathComponent(".swiftlint.yml")
        let baseYAML = """
        analyzer_rules:
          - unused_declaration
        """
        try baseYAML.write(to: baseConfigPath, atomically: true, encoding: .utf8)

        _ = try ImpactSimulatorTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let value = 1\n"
        )

        let workspace = Workspace(path: tempDir)
        let (mockCLI, store) = await Self.makeConfigSnapshotCLI()

        _ = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "unused_declaration",
                workspace: workspace,
                baseConfigPath: baseConfigPath,
                isOptIn: false,
                isAnalyzer: true
            )
        }

        let configs = await store.configs
        let captured = try #require(configs.first)
        let occurrences = captured.analyzerRules?.filter { $0 == "unused_declaration" }.count ?? 0
        #expect(occurrences == 1)
    }
}
