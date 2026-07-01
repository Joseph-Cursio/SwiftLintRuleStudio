//
//  ImpactSimulatorOverridesTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Verifies that parameter overrides supplied to simulateRule(...) make it
//  into the temporary SwiftLint config the simulator generates, so the lint
//  pass uses the user's unsaved editor values rather than the workspace YAML.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

/// Sendable holder so the @Sendable lintCommandHandler closure can stash the
/// captured config text for the test body to read after the call returns.
private actor CapturedConfig {
    private(set) var value: String?

    func set(_ text: String) { self.value = text }
}

struct ImpactSimulatorOverridesTests {
    @Test("parameterOverrides land in the temp config the simulator generates")
    func testParameterOverridesWrittenToTempConfig() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        _ = try ImpactSimulatorTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let x = 1\n"
        )

        // Pre-existing workspace config with the default parameter value.
        let workspaceConfigPath = tempDir.appendingPathComponent(".swiftlint.yml")
        try """
        cyclomatic_complexity:
          warning: 10
        """.write(to: workspaceConfigPath, atomically: true, encoding: .utf8)

        let workspace = Workspace(path: tempDir)
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLIActor(violations: [])

        // Capture the temp config's contents at lint time, before the simulator
        // deletes it via its `defer` cleanup.
        let captured = CapturedConfig()
        await mockCLI.setLintCommandHandler { @Sendable _, workspacePath in
            let rootConfigPath = workspacePath.appendingPathComponent(".swiftlint.yml")
            if let text = try? String(contentsOf: rootConfigPath, encoding: .utf8) {
                await captured.set(text)
            }
            return Data("[]".utf8)
        }

        _ = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "cyclomatic_complexity",
                workspace: workspace,
                baseConfigPath: workspaceConfigPath,
                options: RuleSimulationOptions(parameterOverrides: [
                    "warning": AnyCodable(1),
                    "error": AnyCodable(2)
                ])
            )
        }

        let yaml = try #require(await captured.value, "Expected lintCommandHandler to capture a config")
        // The temp config should reflect the overrides (1/2), not the workspace
        // YAML's saved value (10).
        #expect(yaml.contains("warning: 1"))
        #expect(yaml.contains("error: 2"))
        #expect(!yaml.contains("warning: 10"))
    }

    @Test("no overrides → temp config falls back to workspace YAML values")
    func testNoOverridesFallsBackToWorkspaceYAML() async throws {
        let tempDir = try ImpactSimulatorTestHelpers.createTempWorkspaceDirectory()
        defer { ImpactSimulatorTestHelpers.cleanupTempDirectory(tempDir) }

        _ = try ImpactSimulatorTestHelpers.createSwiftFile(
            in: tempDir,
            name: "Test.swift",
            content: "let x = 1\n"
        )

        let workspaceConfigPath = tempDir.appendingPathComponent(".swiftlint.yml")
        try """
        cyclomatic_complexity:
          warning: 15
        """.write(to: workspaceConfigPath, atomically: true, encoding: .utf8)

        let workspace = Workspace(path: tempDir)
        let mockCLI = await ImpactSimulatorTestHelpers.createMockSwiftLintCLIActor(violations: [])

        let captured = CapturedConfig()
        await mockCLI.setLintCommandHandler { @Sendable _, workspacePath in
            let rootConfigPath = workspacePath.appendingPathComponent(".swiftlint.yml")
            if let text = try? String(contentsOf: rootConfigPath, encoding: .utf8) {
                await captured.set(text)
            }
            return Data("[]".utf8)
        }

        _ = try await ImpactSimulatorTestHelpers.withImpactSimulator(swiftLintCLI: mockCLI) { simulator in
            try await simulator.simulateRule(
                ruleId: "cyclomatic_complexity",
                workspace: workspace,
                baseConfigPath: workspaceConfigPath
            )
        }

        let yaml = try #require(await captured.value)
        // Without overrides the saved workspace value passes through unchanged.
        #expect(yaml.contains("warning: 15"))
    }
}
