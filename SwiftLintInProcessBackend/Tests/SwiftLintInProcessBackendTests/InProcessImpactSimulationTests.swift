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
        #expect(counts["force_cast"] == 2, "a rule the nested config disables is enabled there for its turn")
    }

    /// Enabling an opt-in rule used to add it to `opt_in_rules` beside an existing
    /// `only_rules`, which SwiftLint rejects. In-process, SwiftLint rejects a nested config
    /// by ending the process — the app.
    @Test("Simulating an opt-in rule where a nested config uses only_rules counts it there")
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

        #expect(result.violationCount == 2)
    }
}
