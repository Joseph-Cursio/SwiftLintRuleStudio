//
//  ConfigBehaviourBoundaryTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The edges of config handling that no test reached: enabling a rule among
//  several disabled ones, a rule switched off with a quoted boolean, a "did you
//  mean" for a rule id like nothing known, the nearest parent of a nested
//  config, the only_rules notice's count, a workspace's identity, and the
//  wording of a verification mismatch.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct ConfigBehaviourBoundaryTests {

    // MARK: - Enabling a rule

    @Test("enabling one disabled rule leaves the others disabled, and the list absent once empty")
    func enablingKeepsOtherDisabledRules() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["force_cast", "todo"]
        ConfigRuleEnabler.enableRule("todo", in: &config, isOptIn: false, isAnalyzer: false)
        #expect(config.disabledRules == ["force_cast"])
        ConfigRuleEnabler.enableRule("force_cast", in: &config, isOptIn: false, isAnalyzer: false)
        #expect(config.disabledRules == nil)
    }

    // MARK: - Quoted booleans in the legacy rules block

    @Test("a quoted boolean switches a rule in the legacy rules block on or off")
    func quotedBooleanRuleValue() throws {
        let config = try YAMLConfigurationEngine.parse("""
            rules:
              force_cast: "false"
              todo: "true"
            """)
        #expect(config.disabledRules == ["force_cast"])
        #expect(config.rules["todo"]?.enabled == true)
    }

    // MARK: - "Did you mean"

    @Test("an unknown rule id gets a suggestion only when a known id is close to it")
    func didYouMean() throws {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules = ["force_cst": RuleConfiguration(), "qqqqqqqqqq": RuleConfiguration()]
        let result = ConfigurationValidator().validate(config, knownRuleIds: ["force_cast", "line_length"])
        let suggestions = Dictionary(uniqueKeysWithValues: result.warnings.compactMap { warning -> (String, String?)? in
            guard case .rule(let id) = warning.field else { return nil }
            return (id, warning.suggestion)
        })
        #expect(suggestions["force_cst"] == "Did you mean 'force_cast'?")
        #expect(suggestions.keys.contains("qqqqqqqqqq"))
        #expect(suggestions["qqqqqqqqqq"] == .some(nil))
    }

    // MARK: - Config tree

    private static func workspace(_ configs: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigBehaviourBoundaryTests-\(UUID().uuidString)", isDirectory: true)
        for (relative, content) in configs {
            let directory = relative.isEmpty ? root : root.appendingPathComponent(relative, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try content.write(to: directory.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test("a nested config's parent is its nearest ancestor config, not the root")
    func nearestParent() throws {
        let root = try Self.workspace([
            "": "disabled_rules: [todo]",
            "App": "opt_in_rules: [empty_count]",
            "App/Feature": "disabled_rules: [force_cast]"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = ConfigTreeDiscovery().discover(in: root)
        let feature = try #require(tree.configs.first { $0.relativePath.hasSuffix("Feature/.swiftlint.yml") })
        let app = try #require(tree.configs.first { $0.relativePath == "App/.swiftlint.yml" })
        #expect(feature.parentID == app.configPath)
    }

    @Test("the only_rules notice counts the rules, singular for one", arguments: [
        ("only_rules: [todo]", "Only 1 rule run here"),
        ("only_rules: [todo, force_cast]", "Only 2 rules run here")
    ])
    func onlyRulesNotice(config: String, expected: String) throws {
        let root = try Self.workspace(["": config])
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = ConfigTreeDiscovery().discover(in: root)
        let display = ConfigMapPresenter().display(
            for: ResolvedConfigurationEngine().resolve(at: root, in: tree), in: tree
        )
        let notice = try #require(display.onlyRulesNotice)
        #expect(notice.hasPrefix(expected), "got: \(notice)")
    }

    // MARK: - Identity and wording

    @Test("two workspaces with one id but different paths are not the same workspace")
    func workspaceIdentity() {
        let id = UUID()
        let first = Workspace(path: URL(fileURLWithPath: "/tmp/One"), id: id)
        #expect(first == Workspace(path: URL(fileURLWithPath: "/tmp/One"), id: id))
        #expect(first != Workspace(path: URL(fileURLWithPath: "/tmp/Two"), id: id))
        #expect(first != Workspace(path: URL(fileURLWithPath: "/tmp/One"), id: UUID()))
    }

    @Test("a mismatch says which side claimed the rule active")
    func divergenceWording() throws {
        let claimedActive = RuleVerification(ruleIdentifier: "todo", engineClaimsActive: true, swiftLintReported: false)
        let claimedSuppressed = RuleVerification(
            ruleIdentifier: "todo", engineClaimsActive: false, swiftLintReported: true
        )
        #expect(try #require(claimedActive.divergenceDescription).contains("shows it active"))
        #expect(try #require(claimedSuppressed.divergenceDescription).contains("shows it suppressed"))
        #expect(RuleVerification(ruleIdentifier: "todo", engineClaimsActive: true, swiftLintReported: true)
            .divergenceDescription == nil)
    }
}
