//
//  ConfigVerificationHarnessTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for ConfigVerificationHarness — reconciling the resolved-config engine
//  against SwiftLint. The reconciliation logic is tested deterministically with
//  an injected fake linter; one guarded integration test proves the engine
//  matches real SwiftLint end-to-end.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct ConfigVerificationHarnessTests {

    // MARK: - Helpers

    private func layer(_ name: String, isRoot: Bool) -> ConfigLayer {
        ConfigLayer(
            id: UUID(),
            relativePath: isRoot ? ".swiftlint.yml" : "\(name)/.swiftlint.yml",
            depth: isRoot ? 0 : 1,
            isRoot: isRoot,
            displayName: name
        )
    }

    /// Builds a resolved configuration with the given membership/whitelist.
    private func resolved(
        disabled: [String] = [],
        optIn: [String] = [],
        onlyRules: [String]? = nil
    ) -> ResolvedConfiguration {
        let rootLayer = layer("root", isRoot: true)
        return ResolvedConfiguration(
            targetDirectory: URL(fileURLWithPath: "/tmp/probe-target"),
            layerChain: [rootLayer],
            disabledRules: disabled.map { ResolvedRuleDecision(identifier: $0, setBy: rootLayer) },
            optInRules: optIn.map { ResolvedRuleDecision(identifier: $0, setBy: rootLayer) },
            analyzerRules: [],
            onlyRules: onlyRules.map { AttributedValue(value: $0, setBy: rootLayer) },
            ruleConfigurations: [],
            excluded: nil,
            included: nil,
            reporter: nil
        )
    }

    private func probe(_ ruleIdentifier: String) throws -> RuleProbe {
        try #require(RuleProbeLibrary.probe(for: ruleIdentifier))
    }

    // MARK: - engineClaimsRuleActive (pure reconciliation)

    @Test("default-on rule is active unless disabled")
    func testDefaultRuleActiveUnlessDisabled() throws {
        let forceTry = try probe("force_try")
        #expect(ConfigVerificationHarness.engineClaimsRuleActive(forceTry, in: resolved()))
        #expect(ConfigVerificationHarness.engineClaimsRuleActive(
            forceTry, in: resolved(disabled: ["force_try"])
        ) == false)
    }

    @Test("opt-in rule is active only when opted in")
    func testOptInRuleNeedsOptIn() throws {
        let forceUnwrapping = try probe("force_unwrapping")
        #expect(ConfigVerificationHarness.engineClaimsRuleActive(forceUnwrapping, in: resolved()) == false)
        #expect(ConfigVerificationHarness.engineClaimsRuleActive(
            forceUnwrapping, in: resolved(optIn: ["force_unwrapping"])
        ))
    }

    @Test("disabled overrides opt-in")
    func testDisabledOverridesOptIn() throws {
        let forceUnwrapping = try probe("force_unwrapping")
        let config = resolved(disabled: ["force_unwrapping"], optIn: ["force_unwrapping"])
        #expect(ConfigVerificationHarness.engineClaimsRuleActive(forceUnwrapping, in: config) == false)
    }

    @Test("only_rules mode: active iff whitelisted, default-on rules excluded")
    func testOnlyRulesMode() throws {
        let forceCast = try probe("force_cast")
        let forceTry = try probe("force_try")
        let config = resolved(onlyRules: ["force_cast"])
        #expect(ConfigVerificationHarness.engineClaimsRuleActive(forceCast, in: config))
        #expect(ConfigVerificationHarness.engineClaimsRuleActive(forceTry, in: config) == false)
    }

    // MARK: - verify with a fake linter

    @Test("verify flags a divergence when SwiftLint disagrees with the engine")
    func testVerifyDetectsDivergence() async throws {
        // Fake SwiftLint: force_cast and todo fire; force_try does not.
        let firing: Set<String> = ["force_cast", "todo"]
        let harness = ConfigVerificationHarness { probe, _ in firing.contains(probe.ruleIdentifier) }

        // Engine claims all three active (default-on, none disabled).
        let report = try await harness.verify(
            resolved(),
            probes: [try probe("force_try"), try probe("force_cast"), try probe("todo")]
        )

        #expect(report.isConsistent == false)
        #expect(report.divergences.map(\.ruleIdentifier) == ["force_try"])
        #expect(report.matches.count == 2)
        #expect(report.divergences.first?.divergenceDescription?.contains("force_try") == true)
    }

    @Test("verify reports consistency when SwiftLint agrees")
    func testVerifyConsistent() async throws {
        let harness = ConfigVerificationHarness { probe, _ in
            // force_try active and fires; force_unwrapping inactive and silent.
            probe.ruleIdentifier == "force_try"
        }
        let report = try await harness.verify(
            resolved(),
            probes: [try probe("force_try"), try probe("force_unwrapping")]
        )
        #expect(report.isConsistent)
    }

    // MARK: - JSON parsing

    @Test("parseFiredRuleIDs extracts rule ids from SwiftLint JSON")
    func testParseFiredRuleIDs() {
        let json = Data(#"""
        [{"rule_id":"force_cast","file":"/a.swift","line":2,"severity":"Warning","reason":"x"},
         {"rule_id":"todo","file":"/a.swift","line":3,"severity":"Warning","reason":"y"}]
        """#.utf8)
        #expect(ConfigVerificationHarness.parseFiredRuleIDs(from: json) == ["force_cast", "todo"])
        #expect(ConfigVerificationHarness.parseFiredRuleIDs(from: Data("[]".utf8)).isEmpty)
        #expect(ConfigVerificationHarness.parseFiredRuleIDs(from: Data()).isEmpty)
    }

    // MARK: - End-to-end against real SwiftLint (guarded)

    @Test("end-to-end: the engine agrees with SwiftLint across the nested chain")
    @MainActor
    func testOracleEndToEnd() async throws {
        guard let swiftLint = ConfigVerificationHarness.defaultSwiftLintExecutable() else { return }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OracleTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let testsDir = root.appendingPathComponent("Tests", isDirectory: true)
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "opt_in_rules:\n  - force_unwrapping\n"
            .write(to: root.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        try "disabled_rules:\n  - force_unwrapping\n  - force_try\n"
            .write(to: testsDir.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)

        let tree = ConfigTreeDiscovery().discover(in: root)
        let engine = ResolvedConfigurationEngine()
        let harness = ConfigVerificationHarness(
            probeLinter: ConfigVerificationHarness.swiftLintProbeLinter(
                executable: swiftLint,
                workspaceRoot: root
            )
        )

        // In Tests/, force_unwrapping and force_try are disabled; the engine must
        // agree with SwiftLint for every probed rule.
        let testsReport = try await harness.verify(engine.resolve(at: testsDir, in: tree))
        #expect(
            testsReport.isConsistent,
            "Tests/ divergences: \(testsReport.divergences.compactMap(\.divergenceDescription))"
        )

        // At the root, force_unwrapping is opted in (active) and force_try is on.
        let rootReport = try await harness.verify(engine.resolve(at: root, in: tree))
        #expect(
            rootReport.isConsistent,
            "root divergences: \(rootReport.divergences.compactMap(\.divergenceDescription))"
        )
    }
}
