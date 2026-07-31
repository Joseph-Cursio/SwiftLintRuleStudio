//
//  RuleAuditActionWorkspaceTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for the workspace-facing helpers in RuleAuditView+Actions:
//  Swift file counting, configuration loading, and rule-change notification.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
@Suite("RuleAuditView workspace helpers")
struct RuleAuditActionWorkspaceTests {

    // MARK: - Fixtures

    /// Creates an isolated temp directory that the caller is responsible for removing.
    private static func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuleAuditActionWorkspaceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func writeFile(_ relativePath: String, in root: URL, contents: String = "") throws {
        let target = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: target, atomically: true, encoding: .utf8)
    }

    // MARK: - countSwiftFiles

    @Test("Counts Swift files recursively and ignores other extensions")
    func countsSwiftFilesRecursively() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try Self.writeFile("Top.swift", in: root)
        try Self.writeFile("Nested/Deep/Inner.swift", in: root)
        try Self.writeFile("README.md", in: root)
        try Self.writeFile("Nested/config.yml", in: root)

        let count = RuleAuditView.countSwiftFiles(in: Workspace(path: root))

        #expect(count == 2)
    }

    @Test("Excluded directories are skipped wholesale")
    func skipsExcludedDirectories() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try Self.writeFile("Sources/Real.swift", in: root)
        for excluded in DefaultExclusions.pathPatterns {
            try Self.writeFile("\(excluded)/Vendored.swift", in: root)
        }

        let count = RuleAuditView.countSwiftFiles(in: Workspace(path: root))

        #expect(count == 1, "only the non-excluded Swift file should be counted")
    }

    @Test("An empty workspace counts zero Swift files")
    func countsZeroForEmptyWorkspace() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(RuleAuditView.countSwiftFiles(in: Workspace(path: root)) == 0)
    }

    @Test("A nonexistent workspace path counts zero rather than throwing")
    func countsZeroForMissingPath() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        #expect(RuleAuditView.countSwiftFiles(in: Workspace(path: missing)) == 0)
    }

    // MARK: - loadConfiguration

    @Test("Loads a valid configuration from the workspace config path")
    func loadsValidConfiguration() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try Self.writeFile(
            ".swiftlint.yml",
            in: root,
            contents: """
            disabled_rules:
              - force_cast
            opt_in_rules:
              - explicit_init
            """
        )

        let config = RuleAuditView.loadConfiguration(for: Workspace(path: root))

        #expect(config.disabledRules?.contains("force_cast") == true)
        #expect(config.optInRules?.contains("explicit_init") == true)
    }

    @Test("A missing config file falls back to an empty configuration")
    func fallsBackWhenConfigMissing() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let config = RuleAuditView.loadConfiguration(for: Workspace(path: root))

        #expect(config.disabledRules == nil)
        #expect(config.optInRules == nil)
        #expect(config.rules.isEmpty)
    }

    @Test("A workspace with no configPath derives .swiftlint.yml from the root")
    func derivesConfigPathWhenNil() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try Self.writeFile(
            ".swiftlint.yml",
            in: root,
            contents: """
            disabled_rules:
              - todo
            """
        )

        var workspace = Workspace(path: root)
        workspace.configPath = nil

        let config = RuleAuditView.loadConfiguration(for: workspace)

        #expect(config.disabledRules?.contains("todo") == true)
    }

    // MARK: - postRuleChangeNotification

    @Test("Posting carries the rule ids in userInfo")
    func postsRuleChangeNotification() async {
        let ruleIds = ["force_cast", "explicit_init"]

        let received: [String] = await withCheckedContinuation { continuation in
            nonisolated(unsafe) var token: NSObjectProtocol?
            token = NotificationCenter.default.addObserver(
                forName: .ruleConfigurationDidChange,
                object: nil,
                queue: .main
            ) { notification in
                guard let posted = notification.userInfo?["ruleIds"] as? [String],
                      Set(posted) == Set(ruleIds) else {
                    // Another suite may post concurrently; keep waiting for ours.
                    return
                }
                if let token { NotificationCenter.default.removeObserver(token) }
                continuation.resume(returning: posted)
            }

            RuleAuditView.postRuleChangeNotification(ruleIds: ruleIds)
        }

        #expect(Set(received) == Set(ruleIds))
    }
}
