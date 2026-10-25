//
//  RuleListsDeprecatedAliasTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  SwiftLint reads a deprecated alias in any rule list as its rule: `disabled_rules:
//  [if_let_shadowing]` turns `shorthand_optional_binding` off. The app compared ids as
//  written, so that rule showed as on, and turning it on left the alias in `disabled_rules`
//  and the rule off.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct RuleListsDeprecatedAliasTests {
    private typealias Config = YAMLConfigurationEngine.YAMLConfig

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

    private func enabled(_ rule: Rule, _ config: Config) -> Bool {
        RuleEnablementResolver.isRuleEnabled(rule, config: config)
    }

    // MARK: - Reading

    @Test("currentName maps each alias to its rule and leaves every other id alone")
    func currentNameMapsAliases() {
        #expect(SwiftLintDeprecations.currentName(of: "variable_name") == "identifier_name")
        #expect(SwiftLintDeprecations.currentName(of: "if_let_shadowing") == "shorthand_optional_binding")
        #expect(SwiftLintDeprecations.currentName(of: "identifier_name") == "identifier_name")
        // Superseded but still a rule of its own, not an alias.
        #expect(SwiftLintDeprecations.currentName(of: "generic_type_name") == "generic_type_name")
    }

    @Test("an alias in disabled_rules turns its rule off")
    func aliasInDisabledRules() {
        let config = Config.ruleLists(disabled: ["variable_name"])

        #expect(!enabled(rule("identifier_name"), config))
        #expect(enabled(rule("line_length"), config))
    }

    @Test("an alias in opt_in_rules turns its rule on")
    func aliasInOptInRules() {
        let config = Config.ruleLists(optIn: ["if_let_shadowing"])

        #expect(enabled(rule("shorthand_optional_binding", kind: .optIn), config))
    }

    @Test("an alias in only_rules is on, and its rule's current name with it")
    func aliasInOnlyRules() {
        let config = Config.ruleLists(only: ["variable_name", "force_cast"])

        #expect(enabled(rule("identifier_name"), config))
        #expect(enabled(rule("force_cast"), config))
        #expect(!enabled(rule("line_length"), config))
    }

    @Test("the rule browser shows a rule disabled by its alias as off")
    func registrySyncReadsAliases() {
        let registry = RuleRegistry(swiftLintCLI: MockSwiftLintCLIActor(), cacheManager: MockCacheManager())
        registry.setRulesForTesting([
            rule("shorthand_optional_binding", kind: .optIn),
            rule("identifier_name"),
            rule("line_length")
        ])

        registry.syncEnabledStates(with: Config.ruleLists(optIn: ["if_let_shadowing"], disabled: ["variable_name"]))

        let states = Dictionary(uniqueKeysWithValues: registry.rules.map { ($0.id, $0.isEnabled) })
        #expect(states == ["shorthand_optional_binding": true, "identifier_name": false, "line_length": true])
    }

    @Test("the health score doesn't count a rule disabled by its alias")
    func healthCoverageReadsAliases() {
        let analyzer = ConfigurationHealthAnalyzer()
        // One default rule in four, so the score is below its 50% target and moves with it.
        let rules = [rule("identifier_name")]
            + ["empty_count", "first_where", "sorted_imports"].map { rule($0, kind: .optIn) }

        let byAlias = analyzer.analyze(config: Config.ruleLists(disabled: ["variable_name"]), knownRules: rules)
        let byName = analyzer.analyze(config: Config.ruleLists(disabled: ["identifier_name"]), knownRules: rules)

        let unrestricted = analyzer.analyze(config: Config(), knownRules: rules)
        #expect(byAlias.breakdown.rulesCoverage == byName.breakdown.rulesCoverage)
        #expect(byAlias.breakdown.rulesCoverage < unrestricted.breakdown.rulesCoverage)
    }

    // MARK: - Turning rules on

    @Test("enabling a rule takes its alias out of disabled_rules")
    func enableRemovesAliasFromDisabledRules() {
        var config = Config.ruleLists(disabled: ["if_let_shadowing", "todo"])

        config.enableRule("shorthand_optional_binding", kind: .optIn)

        #expect(config.disabledRules == ["todo"])
        #expect(config.optInRules == ["shorthand_optional_binding"])
        #expect(enabled(rule("shorthand_optional_binding", kind: .optIn), config))
    }

    @Test("enabling a standard rule disabled only by its alias drops the list")
    func enableStandardRuleDisabledByAlias() {
        var config = Config.ruleLists(disabled: ["variable_name"])

        config.enableRule("identifier_name", kind: .standard)

        #expect(config.disabledRules == nil)
        #expect(enabled(rule("identifier_name"), config))
    }

    @Test("a rule a list already names by its alias isn't listed again")
    func enableKeepsAnExistingAlias() {
        var optIn = Config.ruleLists(optIn: ["if_let_shadowing"])
        optIn.enableRule("shorthand_optional_binding", kind: .optIn)
        #expect(optIn.optInRules == ["if_let_shadowing"])

        var only = Config.ruleLists(only: ["variable_name", "force_cast"])
        only.enableRule("identifier_name", kind: .standard)
        #expect(only.onlyRules == ["variable_name", "force_cast"])
    }

    // MARK: - Turning rules off

    @Test("disabling a rule its alias already disables adds nothing")
    func disableDoesNotDuplicateAlias() throws {
        var config = Config.ruleLists(disabled: ["variable_name"])

        try config.disableRule("identifier_name", kind: .standard)

        #expect(config.disabledRules == ["variable_name"])
        #expect(!enabled(rule("identifier_name"), config))
    }

    @Test("disabling a rule takes its alias out of opt_in_rules and only_rules")
    func disableRemovesAliasFromEnablingLists() throws {
        var optIn = Config.ruleLists(optIn: ["if_let_shadowing", "empty_count"])
        try optIn.disableRule("shorthand_optional_binding", kind: .optIn)
        #expect(optIn.optInRules == ["empty_count"])
        #expect(!enabled(rule("shorthand_optional_binding", kind: .optIn), optIn))

        var only = Config.ruleLists(only: ["variable_name", "force_cast"])
        try only.disableRule("identifier_name", kind: .standard)
        #expect(only.onlyRules == ["force_cast"])
        #expect(only.disabledRules == nil)
    }

    @Test("disabling every rule only_rules names, by alias or not, is refused")
    func disableRefusesToEmptyOnlyRulesThroughAliases() {
        var config = Config.ruleLists(only: ["variable_name", "force_cast"])
        let start = config

        #expect(throws: YAMLConfigError.self) {
            try config.disableRules(["identifier_name", "force_cast"]) { _ in .standard }
        }
        #expect(config == start)
    }

    // MARK: - Repair

    @Test("the repair drops a rule from only_rules when disabled_rules names it by its alias")
    func repairMatchesAliasInDisabledRules() {
        let config = Config.ruleLists(only: ["identifier_name", "force_cast"], disabled: ["variable_name"])

        let repaired = config.normalizedRuleLists()

        #expect(repaired.onlyRules == ["force_cast"])
        #expect(repaired.disabledRules == nil)
        #expect(!enabled(rule("identifier_name"), config))
    }

    @Test("the repair doesn't fold in an alias of a rule only_rules already lists")
    func repairDeduplicatesByRule() {
        let config = Config.ruleLists(only: ["shorthand_optional_binding"], optIn: ["if_let_shadowing", "empty_count"])

        let repaired = config.normalizedRuleLists()

        #expect(repaired.onlyRules == ["shorthand_optional_binding", "empty_count"])
        #expect(repaired.optInRules == nil)
    }
}
