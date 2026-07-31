//
//  RuleAuditActionInjectionTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for the enable path once its collaborators are passed in: the guard
//  that decides whether there is anything to write to, rule classification,
//  and the configuration write itself.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
@Suite("RuleAuditView enable path")
struct RuleAuditActionInjectionTests {

    // MARK: - Fixtures

    private static func makeRule(
        _ identifier: String,
        isOptIn: Bool = false,
        isAnalyzer: Bool = false
    ) -> Rule {
        Rule(
            id: identifier,
            name: identifier,
            description: "desc for \(identifier)",
            category: .lint,
            isOptIn: isOptIn,
            isAnalyzer: isAnalyzer
        )
    }

    /// A workspace with a `.swiftlint.yml` containing `configContents`. The
    /// default is an empty rule list rather than an empty file, because the
    /// engine rejects a zero-byte document as unparseable.
    private static func makeWorkspace(
        configContents: String = "disabled_rules: []\n"
    ) throws -> Workspace {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuleAuditActionInjectionTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try configContents.write(
            to: root.appendingPathComponent(".swiftlint.yml"),
            atomically: true,
            encoding: .utf8
        )
        return Workspace(path: root)
    }

    // MARK: - enableConfigPath (the guard)

    @Test("No current workspace means there is nothing to enable into")
    func enableGuardRejectsMissingWorkspace() {
        #expect(RuleAuditView.enableConfigPath(for: nil) == nil)
    }

    @Test("A workspace with no configuration file is rejected")
    func enableGuardRejectsMissingConfigPath() {
        var workspace = Workspace(path: URL(fileURLWithPath: "/tmp/nowhere"))
        workspace.configPath = nil

        #expect(RuleAuditView.enableConfigPath(for: workspace) == nil)
    }

    @Test("A workspace with a configuration file yields its path")
    func enableGuardAcceptsConfiguredWorkspace() throws {
        let workspace = try Self.makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        #expect(RuleAuditView.enableConfigPath(for: workspace) == workspace.configPath)
    }

    // MARK: - ruleClassification

    @Test("Opt-in and analyzer rules are routed to separate sets")
    func classifiesRulesIntoDisjointSets() {
        let rules = [
            Self.makeRule("plain"),
            Self.makeRule("opted_in", isOptIn: true),
            Self.makeRule("analyzed", isAnalyzer: true)
        ]

        let classification = RuleAuditView.ruleClassification(from: rules)

        #expect(classification.optInRuleIds == ["opted_in"])
        #expect(classification.analyzerRuleIds == ["analyzed"])
    }

    @Test("A rule that is both opt-in and analyzer counts only as an analyzer")
    func analyzerWinsOverOptIn() {
        let rules = [Self.makeRule("both", isOptIn: true, isAnalyzer: true)]

        let classification = RuleAuditView.ruleClassification(from: rules)

        #expect(classification.analyzerRuleIds == ["both"])
        #expect(classification.optInRuleIds.isEmpty)
    }

    @Test("No rules classify to empty sets")
    func classifiesEmptyRuleList() {
        let classification = RuleAuditView.ruleClassification(from: [])

        #expect(classification.optInRuleIds.isEmpty)
        #expect(classification.analyzerRuleIds.isEmpty)
    }

    // MARK: - enableRules

    @Test("Enabling clears the rule from disabled_rules")
    func enableRulesPersistsToDisk() throws {
        let workspace = try Self.makeWorkspace(configContents: "disabled_rules:\n  - force_cast\n")
        let configPath = try #require(workspace.configPath)
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        try RuleAuditView.enableRules(
            ["force_cast"],
            configPath: configPath,
            rules: [Self.makeRule("force_cast")]
        )

        // A default rule is enabled by *absence* from disabled_rules, not by an
        // explicit entry, so assert the meaning via the same predicate the audit
        // reads with rather than by matching text.
        let reloaded = RuleAuditView.loadConfiguration(for: workspace)
        #expect(reloaded.disabledRules?.contains("force_cast") != true)
        #expect(RuleAuditView.isRuleEnabled(Self.makeRule("force_cast"), config: reloaded))
    }

    @Test("Enabling routes an opt-in rule into opt_in_rules")
    func enableRulesRoutesOptInRule() throws {
        let workspace = try Self.makeWorkspace()
        let configPath = try #require(workspace.configPath)
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        try RuleAuditView.enableRules(
            ["explicit_init"],
            configPath: configPath,
            rules: [Self.makeRule("explicit_init", isOptIn: true)]
        )

        let reloaded = RuleAuditView.loadConfiguration(for: workspace)
        #expect(reloaded.optInRules?.contains("explicit_init") == true)
        #expect(reloaded.analyzerRules?.contains("explicit_init") != true)
    }

    @Test("Enabling routes an analyzer rule into analyzer_rules")
    func enableRulesRoutesAnalyzerRule() throws {
        let workspace = try Self.makeWorkspace()
        let configPath = try #require(workspace.configPath)
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        try RuleAuditView.enableRules(
            ["unused_declaration"],
            configPath: configPath,
            rules: [Self.makeRule("unused_declaration", isAnalyzer: true)]
        )

        let reloaded = RuleAuditView.loadConfiguration(for: workspace)
        #expect(reloaded.analyzerRules?.contains("unused_declaration") == true)
        #expect(reloaded.optInRules?.contains("unused_declaration") != true)
    }

    @Test("A rule unknown to the registry is enabled as a default rule")
    func enableRulesHandlesUnknownRule() throws {
        // Start with it disabled so clearing that is a real change, and pass an
        // empty rule list so the enable path has no classification to go on.
        let workspace = try Self.makeWorkspace(
            configContents: "disabled_rules:\n  - mystery_rule\n"
        )
        let configPath = try #require(workspace.configPath)
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        try RuleAuditView.enableRules(["mystery_rule"], configPath: configPath, rules: [])

        let reloaded = RuleAuditView.loadConfiguration(for: workspace)
        #expect(reloaded.disabledRules?.contains("mystery_rule") != true)
        #expect(RuleAuditView.isRuleEnabled(Self.makeRule("mystery_rule"), config: reloaded))
        // An unclassified rule must not be guessed into either special list.
        #expect(reloaded.optInRules?.contains("mystery_rule") != true)
        #expect(reloaded.analyzerRules?.contains("mystery_rule") != true)
    }

    @Test("Enabling announces the change so the rest of the app reloads")
    func enableRulesPostsNotification() throws {
        let workspace = try Self.makeWorkspace()
        let configPath = try #require(workspace.configPath)
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        // Observe with no queue so delivery is synchronous on the posting
        // thread: waiting on a continuation would hang for the full timeout if
        // enableRules ever threw before reaching the post.
        nonisolated(unsafe) var posted: [[String]] = []
        let token = NotificationCenter.default.addObserver(
            forName: .ruleConfigurationDidChange,
            object: nil,
            queue: nil
        ) { notification in
            if let ruleIds = notification.userInfo?["ruleIds"] as? [String] {
                posted.append(ruleIds)
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try RuleAuditView.enableRules(["announced_rule"], configPath: configPath, rules: [])

        #expect(posted.contains(["announced_rule"]))
    }

    @Test("Enabling nothing still leaves a readable configuration")
    func enableRulesWithNoIdsIsHarmless() throws {
        let workspace = try Self.makeWorkspace(configContents: "disabled_rules:\n  - todo\n")
        let configPath = try #require(workspace.configPath)
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        try RuleAuditView.enableRules([], configPath: configPath, rules: [])

        let reloaded = RuleAuditView.loadConfiguration(for: workspace)
        #expect(reloaded.disabledRules?.contains("todo") == true)
    }

    @Test("A configuration that cannot be parsed surfaces as a thrown error")
    func enableRulesThrowsOnUnreadableConfig() throws {
        let workspace = try Self.makeWorkspace(configContents: "")
        let configPath = try #require(workspace.configPath)
        defer { try? FileManager.default.removeItem(at: workspace.path) }

        // The view turns this into the error alert; here it just has to escape
        // rather than be swallowed.
        #expect(throws: (any Error).self) {
            try RuleAuditView.enableRules(["any_rule"], configPath: configPath, rules: [])
        }
    }
}
