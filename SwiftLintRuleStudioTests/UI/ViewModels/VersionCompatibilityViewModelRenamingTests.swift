//
//  VersionCompatibilityViewModelRenamingTests.swift
//  SwiftLintRuleStudioTests
//
//  What "Fix" writes to the config file: VersionCompatibilityViewModel.applyRenaming
//  against the real checker and a real file
//

import Foundation
import SwiftLintCLISeam
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

/// A CLI that only reports its version; "Fix" never lints.
private struct VersionOnlyCLI: SwiftLintCLIProtocol {
    let version: String

    func getVersion() throws -> String { version }
    func detectSwiftLintPath() throws -> URL { URL(fileURLWithPath: "/usr/bin/swiftlint") }
    func executeRulesCommand() throws -> Data { Data() }
    func executeRuleDetailCommand(ruleId _: String) throws -> Data { Data() }
    func generateDocsForRule(ruleId _: String) throws -> String { "" }
    func executeLintCommand(configPath _: URL?, workspacePath _: URL) throws -> Data { Data() }
}

@MainActor
struct VersionCompatibilityViewModelRenamingTests {

    private static let rename = RenamedRuleInfo(
        id: "redundant_self_in_closure", oldRuleId: "redundant_self_in_closure", newRuleId: "redundant_self"
    )

    /// Writes `yaml` as a workspace's `.swiftlint.yml`, applies the rename as "Fix" does, waits
    /// for the re-check, and returns the view model and the saved file's text.
    private func fix(_ yaml: String) async throws -> (VersionCompatibilityViewModel, saved: String) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        try yaml.write(to: configPath, atomically: true, encoding: .utf8)

        let viewModel = VersionCompatibilityViewModel(
            checker: VersionCompatibilityChecker(),
            swiftLintCLI: VersionOnlyCLI(version: "0.65.0"),
            configPath: configPath
        )
        viewModel.applyRenaming(Self.rename)
        await viewModel.checkTask?.value
        return (viewModel, try String(contentsOf: configPath, encoding: .utf8))
    }

    /// Issue #83's file lists its rules under `only_rules` and `analyzer_rules`. "Fix" renamed
    /// only in the rule configurations, `disabled_rules` and `opt_in_rules`, so a renamed rule in
    /// either of the other lists stayed flagged however often it was fixed. (The rename does not
    /// care which list a rule belongs in, so the alias stands in for an analyzer rule here.)
    @Test("Fix renames the rule in only_rules, analyzer_rules and its configuration")
    func renamesInEveryList() async throws {
        let (viewModel, saved) = try await fix("""
            only_rules:
              - redundant_self_in_closure
              - force_cast
            analyzer_rules:
              - redundant_self_in_closure
            redundant_self_in_closure:
              severity: error

            """)
        let config = try YAMLConfigurationEngine.parse(saved)
        #expect(viewModel.error == nil)
        #expect(config.onlyRules == ["redundant_self", "force_cast"])
        #expect(config.analyzerRules == ["redundant_self"])
        #expect(config.rules["redundant_self"]?.severity == .error)
        #expect(config.ruleIdsAsWritten.contains("redundant_self_in_closure") == false)
        #expect(viewModel.report?.renamedRules.isEmpty == true)
    }

    @Test("Fix keeps the configuration the new rule already has and leaves no duplicate")
    func keepsExistingNewRule() async throws {
        let (viewModel, saved) = try await fix("""
            opt_in_rules:
              - redundant_self_in_closure
              - redundant_self
            redundant_self_in_closure:
              severity: error
            redundant_self:
              severity: warning

            """)
        let config = try YAMLConfigurationEngine.parse(saved)
        #expect(viewModel.error == nil)
        #expect(config.optInRules == ["redundant_self"])
        #expect(config.rules["redundant_self"]?.severity == .warning)
        #expect(config.rules["redundant_self_in_closure"] == nil)
    }

    /// SwiftLint rejects a file that configures both an alias and its rule, so Fix merges them.
    @Test("Fix merges the old rule's settings into the new rule's")
    func mergesBothConfigurations() async throws {
        let (viewModel, saved) = try await fix("""
            redundant_self_in_closure:
              only_in_closures: false
            redundant_self:
              severity: warning

            """)
        let config = try YAMLConfigurationEngine.parse(saved)
        #expect(viewModel.error == nil)
        #expect(config.rules["redundant_self"]?.severity == .warning)
        #expect(config.rules["redundant_self"]?.parameters?["only_in_closures"]?.value as? Bool == false)
        #expect(config.ruleIdsAsWritten == ["redundant_self"])
    }

    /// `redundant_self_in_closure: error` is a severity shorthand the engine holds as a passthrough
    /// node, not in `rules`. "Fix" left the key behind, and the re-check reported the config clean.
    @Test("Fix renames a rule configured by a severity shorthand")
    func renamesSeverityShorthand() async throws {
        let (viewModel, saved) = try await fix("redundant_self_in_closure: error\nline_length: 120\n")
        #expect(viewModel.error == nil)
        #expect(saved.contains("redundant_self: error"))
        #expect(saved.contains("redundant_self_in_closure") == false)
        #expect(viewModel.report?.renamedRules.isEmpty == true)
    }
}
