//
//  RuleEnablementResolverOnlyRulesTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  How the resolver reads only_rules (issue #83): only a non-empty list is an allowlist,
//  SwiftLint unions it with analyzer_rules, and a file SwiftLint rejects reads as its repair.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct RuleEnablementResolverOnlyRulesTests {

    private func rule(_ ruleId: String, kind: RuleListKind = .standard) -> Rule {
        Rule(
            id: ruleId,
            name: ruleId,
            description: "desc",
            category: .style,
            isOptIn: kind != .standard,
            isAnalyzer: kind == .analyzer
        )
    }

    private func enabled(_ rule: Rule, _ config: YAMLConfigurationEngine.YAMLConfig) -> Bool {
        RuleEnablementResolver.isRuleEnabled(rule, config: config)
    }

    @Test("an empty only_rules is no allowlist at all")
    func emptyOnlyRulesIsDefaultMode() {
        let config = YAMLConfigurationEngine.YAMLConfig.ruleLists(only: [], optIn: ["empty_count"])

        #expect(enabled(rule("force_cast"), config))
        #expect(enabled(rule("empty_count", kind: .optIn), config))
        #expect(!enabled(rule("first_where", kind: .optIn), config))
    }

    @Test("only_rules runs alongside analyzer_rules, and nothing else")
    func onlyRulesUnionsAnalyzerRules() {
        let config = YAMLConfigurationEngine.YAMLConfig.ruleLists(only: ["force_cast"], analyzer: ["explicit_self"])

        #expect(enabled(rule("force_cast"), config))
        #expect(enabled(rule("explicit_self", kind: .analyzer), config))
        #expect(!enabled(rule("unused_import", kind: .analyzer), config))
        #expect(!enabled(rule("line_length"), config))
    }

    @Test("a file SwiftLint rejects shows as its repair will write it")
    func conflictResolvesAsRepaired() {
        // only_rules + opt_in_rules + disabled_rules, as the old Rule Browser left it:
        // the opt-in it enabled joins the allowlist, the rule it disabled leaves it.
        let config = YAMLConfigurationEngine.YAMLConfig.ruleLists(
            only: ["force_cast", "line_length"],
            optIn: ["empty_count"],
            disabled: ["line_length"]
        )

        #expect(enabled(rule("force_cast"), config))
        #expect(enabled(rule("empty_count", kind: .optIn), config))
        #expect(!enabled(rule("line_length"), config))
        #expect(!enabled(rule("todo"), config))
    }
}
