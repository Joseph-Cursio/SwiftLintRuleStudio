//
//  ImpactSimulatorOnlyRuleEndToEndTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  A simulation lints the measured rule alone where that counts what a lint of every rule
//  would, driving the real swiftlint binary: the rule keeps its settings and nested disables,
//  and the rules `--only-rule` would miscount are still linted with every rule.
//
//  Requires SwiftLint to be installed.
//

import Foundation
import SwiftLintCLIBackend
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct ImpactSimulatorOnlyRuleEndToEndTests {

    nonisolated private func isSwiftLintAvailable() -> Bool {
        ["/opt/homebrew/bin/swiftlint", "/usr/local/bin/swiftlint", "/usr/bin/swiftlint"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func makeTempWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnlyRuleEndToEndTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func simulate(_ ruleId: String, in root: URL, isOptIn: Bool = false) async throws -> RuleImpactResult {
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnlyRuleEndToEndTests", isDirectory: true)
            .appendingPathComponent("cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let simulator = ImpactSimulator(
            swiftLintCLI: SwiftLintCLIActor(cacheManager: CacheManager(cacheDirectory: cacheDir))
        )
        let workspace = Workspace(path: root)
        return try await simulator.simulateRule(
            ruleId: ruleId,
            workspace: workspace,
            baseConfigPath: workspace.configPath,
            options: RuleSimulationOptions(isOptIn: isOptIn)
        )
    }

    @Test("a rule linted alone keeps its settings from the root and its disables in nested configs")
    func ruleAloneKeepsWhatTheConfigsSay() async throws {
        guard isSwiftLintAvailable() else {
            #expect(Bool(false), "SwiftLint not installed - skipping integration test")
            return
        }
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            "disabled_rules:\n  - line_length\nline_length:\n  warning: 20\n",
            to: root.appendingPathComponent(".swiftlint.yml")
        )
        try write("let short = 1\nlet aLineLongerThanTwenty = 1\n", to: root.appendingPathComponent("A.swift"))
        try write("disabled_rules:\n  - line_length\n", to: root.appendingPathComponent("Legacy/.swiftlint.yml"))
        try write("let aLineLongerThanTwenty = 1\n", to: root.appendingPathComponent("Legacy/B.swift"))

        let result = try await simulate("line_length", in: root)

        #expect(result.violationCount == 1)
        #expect(result.affectedFiles == ["A.swift"])
    }

    @Test("superfluous_disable_command counts the disables of rules that ran and found nothing")
    func superfluousDisableCommandCountsAgainstEveryRule() async throws {
        guard isSwiftLintAvailable() else {
            #expect(Bool(false), "SwiftLint not installed - skipping integration test")
            return
        }
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            "disabled_rules:\n  - superfluous_disable_command\n",
            to: root.appendingPathComponent(".swiftlint.yml")
        )
        try write(
            """
            let value: Any = 1
            // swiftlint:disable:next force_cast
            let cast = value as! Int
            // swiftlint:disable:next force_try
            let plain = cast

            """,
            to: root.appendingPathComponent("A.swift")
        )

        let result = try await simulate("superfluous_disable_command", in: root)

        // force_try's disable is superfluous; force_cast's suppresses a violation.
        #expect(result.violationCount == 1)
    }

    @Test("custom_rules counts each custom rule, under its own name")
    func customRulesCountEachCustomRule() async throws {
        guard isSwiftLintAvailable() else {
            #expect(Bool(false), "SwiftLint not installed - skipping integration test")
            return
        }
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            "disabled_rules:\n  - custom_rules\ncustom_rules:\n  no_number:\n    regex: NSNumber\n",
            to: root.appendingPathComponent(".swiftlint.yml")
        )
        try write(
            "custom_rules:\n  no_print:\n    regex: print\n",
            to: root.appendingPathComponent("Sub/.swiftlint.yml")
        )
        try write("let number = NSNumber(value: 1)\n", to: root.appendingPathComponent("A.swift"))
        try write("print(1)\n", to: root.appendingPathComponent("Sub/B.swift"))

        let result = try await simulate("custom_rules", in: root)

        #expect(Set(result.violations.map(\.ruleID)) == ["no_number", "no_print"])
    }

    @Test("a nested only_rules without the rule keeps it off beneath it")
    func nestedOnlyRulesKeepTheRuleOff() async throws {
        guard isSwiftLintAvailable() else {
            #expect(Bool(false), "SwiftLint not installed - skipping integration test")
            return
        }
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = "let values: [Int] = []\nlet isEmpty = values.count == 0\n"
        try write("", to: root.appendingPathComponent(".swiftlint.yml"))
        try write(source, to: root.appendingPathComponent("A.swift"))
        try write("only_rules:\n  - force_cast\n", to: root.appendingPathComponent("Strict/.swiftlint.yml"))
        try write(source, to: root.appendingPathComponent("Strict/B.swift"))

        let result = try await simulate("empty_count", in: root, isOptIn: true)

        #expect(result.affectedFiles == ["A.swift"])
    }
}
