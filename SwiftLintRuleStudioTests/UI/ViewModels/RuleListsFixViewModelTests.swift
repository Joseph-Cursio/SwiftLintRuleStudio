//
//  RuleListsFixViewModelTests.swift
//  SwiftLintRuleStudioTests
//
//  The rule-lists banner's repair: previewed, then written with a backup (issue #83).
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

// Serialized: two tests watch for the repair's announcement, which the other would post.
@MainActor
@Suite(.serialized)
struct RuleListsFixViewModelTests {

    private static let conflicted = """
    included:
      - Sources
    only_rules:
      - force_cast
      - unused_import
    opt_in_rules:
      - empty_count
    analyzer_rules:
      - unused_import

    """

    private func backups(beside configPath: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: configPath.deletingLastPathComponent().path)
            .filter { $0.hasPrefix(".swiftlint.yml.") && $0.hasSuffix(".backup") }
    }

    @Test("The fix is previewed before anything is written")
    func prepareFixPreviewsWithoutWriting() throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: Self.conflicted)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }
        let viewModel = RuleListsFixViewModel(configPath: configPath)

        viewModel.prepareFix()

        let diff = try #require(viewModel.diff)
        #expect(diff.before.contains("opt_in_rules"))
        #expect(!diff.after.contains("opt_in_rules"))
        #expect(try String(contentsOf: configPath, encoding: .utf8) == Self.conflicted)
    }

    @Test("Applying the fix writes a file SwiftLint accepts, keeps a backup, and announces it")
    func applyFixWritesTheRepair() throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: Self.conflicted)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }
        let viewModel = RuleListsFixViewModel(configPath: configPath)
        // No queue, so delivery is synchronous on the posting thread.
        nonisolated(unsafe) var announced = false
        let observer = NotificationCenter.default.addObserver(
            forName: .ruleConfigurationDidChange, object: nil, queue: nil
        ) { notification in
            if notification.userInfo?["ruleListsRepair"] as? Bool == true { announced = true }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        viewModel.prepareFix()
        viewModel.applyFix()

        let saved = try YAMLConfigurationEngine.loadConfig(at: configPath)
        #expect(saved.onlyRules == ["force_cast", "empty_count"])
        #expect(saved.optInRules == nil)
        #expect(saved.analyzerRules == ["unused_import"])
        #expect(saved.included == ["Sources"])
        #expect(ConfigRuleListsProblem(saved) == nil)
        #expect(viewModel.diff == nil)
        #expect(viewModel.errorMessage == nil)
        #expect(try backups(beside: configPath).count == 1)
        #expect(announced)
    }

    @Test("Cancelling leaves the file alone")
    func cancelWritesNothing() throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: Self.conflicted)
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }
        let viewModel = RuleListsFixViewModel(configPath: configPath)

        viewModel.prepareFix()
        viewModel.cancel()
        viewModel.applyFix()

        #expect(viewModel.diff == nil)
        #expect(try String(contentsOf: configPath, encoding: .utf8) == Self.conflicted)
    }

    @Test("A file fixed since the banner looked opens no preview, only a refresh")
    func prepareFixOnCleanFileOnlyAnnounces() throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(
            content: "only_rules:\n  - force_cast\n"
        )
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }
        let viewModel = RuleListsFixViewModel(configPath: configPath)
        // No queue, so delivery is synchronous on the posting thread.
        nonisolated(unsafe) var announced = false
        let observer = NotificationCenter.default.addObserver(
            forName: .ruleConfigurationDidChange, object: nil, queue: nil
        ) { notification in
            if notification.userInfo?["ruleListsRepair"] as? Bool == true { announced = true }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        viewModel.prepareFix()

        #expect(viewModel.diff == nil)
        #expect(announced)
    }

    @Test("A repair that can't be written closes the preview and reports why")
    func applyFixFailureClosesThePreview() throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: Self.conflicted)
        let directory = configPath.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            RuleDetailViewModelTestHelpers.cleanupTempFile(configPath)
        }
        let viewModel = RuleListsFixViewModel(configPath: configPath)

        viewModel.prepareFix()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        viewModel.applyFix()

        // The alert is shown by the sheet's presenter, so the sheet has to go first.
        #expect(viewModel.diff == nil)
        #expect(viewModel.errorMessage != nil)
        #expect(try String(contentsOf: configPath, encoding: .utf8) == Self.conflicted)
    }

    @Test("An unreadable file reports why")
    func prepareFixReportsUnreadableFile() throws {
        let configPath = try RuleDetailViewModelTestHelpers.createTempConfigFile(content: "only_rules: [unclosed\n")
        defer { RuleDetailViewModelTestHelpers.cleanupTempFile(configPath) }
        let viewModel = RuleListsFixViewModel(configPath: configPath)

        viewModel.prepareFix()

        #expect(viewModel.diff == nil)
        #expect(viewModel.errorMessage != nil)
    }
}
