import Foundation
import SwiftLintInProcessBackend
import SwiftLintRuleStudioCore
import Testing

/// The Rule Audit, end to end, on the sandboxed edition's in-process SwiftLint.
///
/// A batch simulation mirrors the workspace once and, for each rule, rewrites the
/// mirror's configs to enable that rule and lints again. In-process, that used to go
/// wrong twice over: the mirror's configs were never found (so opt-in rules never ran),
/// and SwiftLint's config caches handed later rules the first rule's settings.
@MainActor
@Suite(.serialized)
struct InProcessImpactSimulationTests {
    private static let source = """
        import Foundation

        let values: [Int] = []
        let isEmpty = values.count == 0
        let number = NSNumber(value: 1) as! Int
        let parsed = Int("1")!

        """

    /// A workspace whose root and `Nested/` folder each hold one Swift file that triggers
    /// `empty_count` and `force_unwrapping` (opt-in) and `force_cast` (on by default). Both
    /// configs disable `force_cast`; the nested one also disables `trailing_newline`, so it
    /// differs from the root and SwiftLint has to merge the two.
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessImpactSimulationTests-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Self.source.write(to: root.appendingPathComponent("Sample.swift"), atomically: true, encoding: .utf8)
        try Self.source.write(to: nested.appendingPathComponent("Inner.swift"), atomically: true, encoding: .utf8)
        try "disabled_rules:\n  - force_cast\n"
            .write(to: root.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        try "disabled_rules:\n  - force_cast\n  - trailing_newline\n"
            .write(to: nested.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        return root
    }

    /// In-process SwiftLint caches the root config merged with a nested config by path.
    /// The mirror's configs are rewritten for each rule, so every rule after the first
    /// would be measured in `Nested/` against the first rule's merge — unless the mirror
    /// moves to a new path for each rule.
    @Test("A batch audit counts each rule in every folder, including one with its own config")
    func batchCountsEachRule() async throws {
        let workspace = Workspace(path: try makeWorkspace())
        let simulator = ImpactSimulator(swiftLintCLI: SwiftLintInProcessActor())

        let batch = try await simulator.simulateRules(
            ruleIds: ["empty_count", "force_unwrapping", "force_cast"],
            workspace: workspace,
            baseConfigPath: workspace.configPath,
            classification: RuleClassification(optInRuleIds: ["empty_count", "force_unwrapping"])
        )

        let counts = Dictionary(uniqueKeysWithValues: batch.results.map { ($0.ruleId, $0.violationCount) })
        #expect(counts["empty_count"] == 2, "opt-in rule found in both folders")
        #expect(counts["force_unwrapping"] == 2, "a later opt-in rule is enabled in the nested folder too")
        // Enable writes only the root config, so the nested config still turns it off there.
        #expect(counts["force_cast"] == 1, "a rule the nested config disables stays off there")
    }

    /// Enabling an opt-in rule used to add it to `opt_in_rules` beside an existing
    /// `only_rules`, which SwiftLint rejects. In-process, SwiftLint rejects a nested config
    /// by ending the process — the app. Enable now leaves nested configs alone, and so does
    /// the simulation: the rule stays off where the nested `only_rules` doesn't list it.
    @Test("Simulating an opt-in rule where a nested config uses only_rules leaves it off there")
    func simulatesOptInRuleUnderNestedOnlyRules() async throws {
        let root = try makeWorkspace()
        try "only_rules:\n  - force_cast\n"
            .write(to: root.appendingPathComponent("Nested/.swiftlint.yml"), atomically: true, encoding: .utf8)
        let workspace = Workspace(path: root)

        let result = try await ImpactSimulator(swiftLintCLI: SwiftLintInProcessActor()).simulateRule(
            ruleId: "empty_count",
            workspace: workspace,
            baseConfigPath: workspace.configPath,
            options: RuleSimulationOptions(isOptIn: true)
        )

        #expect(result.violationCount == 1)
    }

    /// SwiftLint's `Linter` drops analyzer rules when it has no compiler arguments, and a lint
    /// never has any — so linting reports none of an analyzer rule's violations, even where
    /// the code has them. That 0 is why the simulator doesn't lint analyzer rules: it would
    /// show them as safe to enable.
    @Test("Linting reports no analyzer-rule violations, even where the code has them")
    func lintNeverRunsAnalyzerRules() async throws {
        let root = try makeWorkspace()
        try "import Foundation\nimport Combine\n\nlet value = 1\n"
            .write(to: root.appendingPathComponent("Unused.swift"), atomically: true, encoding: .utf8)
        // The opt-in rule is the control: it shows this config was read and the files linted,
        // so the missing analyzer violations mean something.
        try "opt_in_rules:\n  - empty_count\nanalyzer_rules:\n  - unused_import\n"
            .write(to: root.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)

        let data = try await SwiftLintInProcessActor().executeLintCommand(configPath: nil, workspacePath: root)

        let report = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let ruleIds = Set(report.compactMap { $0["rule_id"] as? String })
        #expect(ruleIds.contains("empty_count"), "the config was applied")
        #expect(!ruleIds.contains("unused_import"))
    }

    /// SwiftLint follows a symlinked folder. The mirror used to skip one, so with
    /// `included: [Sources]` and `Sources` a link, every rule linted nothing and measured 0.
    @Test("A rule is measured in a symlinked folder, with the config inside it applied")
    func simulatesThroughSymlinkedFolder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessImpactSimulationTests-\(UUID().uuidString)", isDirectory: true)
        let real = FileManager.default.temporaryDirectory
            .appendingPathComponent("InProcessImpactSimulationTests-real-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: real)
        }
        try Self.source.write(to: real.appendingPathComponent("Linked.swift"), atomically: true, encoding: .utf8)
        // Only the linked folder's own config lowers force_cast to a warning; seeing warnings
        // shows it was mirrored and applied under the link's path.
        try "force_cast:\n  severity: warning\n"
            .write(to: real.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        try "included:\n  - Sources\ndisabled_rules:\n  - force_cast\n"
            .write(to: root.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Sources"), withDestinationURL: real)
        let workspace = Workspace(path: root)

        let result = try await ImpactSimulator(swiftLintCLI: SwiftLintInProcessActor()).simulateRule(
            ruleId: "force_cast",
            workspace: workspace,
            baseConfigPath: workspace.configPath,
            options: RuleSimulationOptions()
        )

        #expect(result.measurement == .measured)
        #expect(result.violationCount == 1)
        #expect(result.violations.first?.filePath == "Sources/Linked.swift")
        #expect(result.violations.allSatisfy { $0.severity == .warning })
    }

    @Test("A batch audit reports an analyzer rule as unmeasurable, not as 0 violations")
    func batchReportsAnalyzerRuleUnmeasurable() async throws {
        let workspace = Workspace(path: try makeWorkspace())
        let simulator = ImpactSimulator(swiftLintCLI: SwiftLintInProcessActor())

        let batch = try await simulator.simulateRules(
            ruleIds: ["empty_count", "unused_import"],
            workspace: workspace,
            baseConfigPath: workspace.configPath,
            classification: RuleClassification(optInRuleIds: ["empty_count"], analyzerRuleIds: ["unused_import"])
        )

        let byRule = Dictionary(uniqueKeysWithValues: batch.results.map { ($0.ruleId, $0) })
        #expect(byRule["empty_count"]?.violationCount == 2)
        #expect(byRule["unused_import"]?.measurement == .unmeasurable(.analyzerRule))
        #expect(batch.safeRules.isEmpty, "neither rule may be offered as safe to enable")
    }
}
