//
//  ResolvedConfigurationEngineTests+OnlyRules.swift
//  SwiftLintRuleStudioTests
//
//  A nested config beneath a layer that declares `only_rules`. A child in default
//  mode edits the whitelist, as SwiftLint's `RulesWrapper.mergeDefaultMode` does;
//  a child's own `only_rules` replaces it. `analyzer_rules` join the whitelist.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

extension ResolvedConfigurationEngineTests {
    @Test("a child's disabled_rules and opt_in_rules edit its parent's only_rules")
    @MainActor
    func testChildEditsParentOnlyRules() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig("only_rules:\n  - force_cast\n  - force_try\n", at: "", in: root)
        try writeConfig("disabled_rules:\n  - force_try\nopt_in_rules:\n  - empty_count\n", at: "Sub", in: root)

        let atSub = resolve(at: "Sub", in: root)
        let only = try #require(atSub.onlyRules)
        #expect(only.identifiers == ["empty_count", "force_cast"])
        #expect(only.declaredBy.isRoot)
        #expect(only.rules.map(\.setBy.displayName) == ["Sub", "root"])
        #expect(atSub.disablingLayer(for: "force_try")?.displayName == "Sub")

        let atRoot = resolve(at: "", in: root)
        #expect(atRoot.onlyRules?.identifiers == ["force_cast", "force_try"])
    }

    @Test("a rule a child both opts in and disables stays out of its parent's only_rules")
    @MainActor
    func testChildContradictionStaysOutOfParentOnlyRules() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig("only_rules:\n  - force_cast\n", at: "", in: root)
        try writeConfig("disabled_rules:\n  - empty_count\nopt_in_rules:\n  - empty_count\n", at: "Sub", in: root)

        let atSub = resolve(at: "Sub", in: root)
        #expect(atSub.onlyRules?.identifiers == ["force_cast"])
    }

    @Test("analyzer_rules join the only_rules of the layer that declares it")
    @MainActor
    func testAnalyzerRulesJoinDeclaredOnlyRules() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig("only_rules:\n  - force_cast\nanalyzer_rules:\n  - unused_import\n", at: "", in: root)

        let resolved = resolve(at: "", in: root)
        #expect(resolved.onlyRules?.identifiers == ["force_cast", "unused_import"])
        #expect(resolved.analyzerRules.map(\.identifier) == ["unused_import"])
    }

    @Test("a child's analyzer_rules join its parent's only_rules, and its disabled_rules remove one")
    @MainActor
    func testChildAnalyzerRulesEditParentOnlyRules() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig("only_rules:\n  - force_cast\nanalyzer_rules:\n  - unused_import\n", at: "", in: root)
        try writeConfig(
            "analyzer_rules:\n  - unused_declaration\n  - capture_variable\n"
                + "disabled_rules:\n  - unused_import\n  - capture_variable\n",
            at: "Sub",
            in: root
        )

        let atSub = resolve(at: "Sub", in: root)
        let only = try #require(atSub.onlyRules)
        #expect(only.identifiers == ["force_cast", "unused_declaration"])
        #expect(only.rules.last?.setBy.displayName == "Sub")
    }

    @Test("a child's only_rules replaces its parent's, analyzer_rules included")
    @MainActor
    func testChildOnlyRulesReplacesParentOnlyRules() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig(
            "only_rules:\n  - force_cast\n  - force_try\nanalyzer_rules:\n  - unused_import\n",
            at: "",
            in: root
        )
        try writeConfig("only_rules:\n  - todo\nanalyzer_rules:\n  - unused_declaration\n", at: "Sub", in: root)

        let atSub = resolve(at: "Sub", in: root)
        let only = try #require(atSub.onlyRules)
        #expect(only.identifiers == ["todo", "unused_declaration"])
        #expect(only.declaredBy.displayName == "Sub")
        #expect(only.rules.allSatisfy { $0.setBy.displayName == "Sub" })
        #expect(atSub.analyzerRules.map(\.identifier) == ["unused_declaration"])
    }
}
