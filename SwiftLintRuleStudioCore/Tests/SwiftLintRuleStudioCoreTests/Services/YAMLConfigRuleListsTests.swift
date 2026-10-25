//
//  YAMLConfigRuleListsTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The rule lists read the way SwiftLint reads them together (issue #83): the mode
//  predicates and turning rules on and off in each mode. The repair is in
//  YAMLConfigRuleListsRepairTests.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct YAMLConfigRuleListsTests {

    private func config(
        only: [String]? = nil,
        optIn: [String]? = nil,
        disabled: [String]? = nil,
        analyzer: [String]? = nil
    ) -> YAMLConfigurationEngine.YAMLConfig {
        .ruleLists(only: only, optIn: optIn, disabled: disabled, analyzer: analyzer)
    }

    // MARK: - Mode predicates

    @Test("only mode needs a non-empty only_rules, as in SwiftLint")
    func usesOnlyRulesNeedsANonEmptyList() {
        #expect(config(only: ["force_cast"]).usesOnlyRules)
        #expect(!config(only: []).usesOnlyRules)
        #expect(!config().usesOnlyRules)
    }

    @Test("only_rules beside a non-empty opt_in_rules or disabled_rules is a conflict")
    func conflictNeedsNonEmptyListsOnBothSides() {
        #expect(config(only: ["force_cast"], optIn: ["empty_count"]).hasOnlyRulesConflict)
        #expect(config(only: ["force_cast"], disabled: ["todo"]).hasOnlyRulesConflict)
        #expect(!config(only: ["force_cast"], optIn: [], disabled: []).hasOnlyRulesConflict)
        #expect(!config(only: [], optIn: ["empty_count"], disabled: ["todo"]).hasOnlyRulesConflict)
        #expect(!config(optIn: ["empty_count"], disabled: ["todo"]).hasOnlyRulesConflict)
    }

    @Test("ids under both only_rules and analyzer_rules are reported in only_rules order")
    func duplicatedAnalyzerRules() {
        let config = config(
            only: ["unused_import", "force_cast", "explicit_self"],
            analyzer: ["explicit_self", "unused_import"]
        )
        #expect(config.rulesInOnlyAndAnalyzerRules == ["unused_import", "explicit_self"])
        #expect(self.config(only: [], analyzer: ["explicit_self"]).rulesInOnlyAndAnalyzerRules.isEmpty)
    }

    @Test("the problem a banner reports, conflict first")
    func problem() {
        #expect(ConfigRuleListsProblem(config(only: ["a"], optIn: ["b"], analyzer: ["a"])) == .onlyRulesConflict)
        #expect(ConfigRuleListsProblem(config(only: ["a", "u"], analyzer: ["u"])) == .analyzerRulesInOnlyRules(["u"]))
        #expect(ConfigRuleListsProblem(config(only: ["a"], analyzer: ["u"])) == nil)
        #expect(ConfigRuleListsProblem(config(optIn: ["b"], disabled: ["c"])) == nil)
    }

    // MARK: - Enabling

    @Test("in only mode an opt-in rule goes into only_rules, never opt_in_rules")
    func enableOptInInOnlyMode() {
        var config = config(only: ["force_cast"])
        config.enableRule("empty_count", kind: .optIn)
        #expect(config.onlyRules == ["force_cast", "empty_count"])
        #expect(config.optInRules == nil)
        #expect(!config.hasOnlyRulesConflict)
    }

    @Test("in only mode a standard rule goes into only_rules")
    func enableStandardInOnlyMode() {
        var config = config(only: ["force_cast"])
        config.enableRule("line_length", kind: .standard)
        #expect(config.onlyRules == ["force_cast", "line_length"])
        #expect(config.disabledRules == nil)
    }

    @Test("in only mode an analyzer rule goes into analyzer_rules only")
    func enableAnalyzerInOnlyMode() {
        var config = config(only: ["force_cast"])
        config.enableRule("unused_import", kind: .analyzer)
        #expect(config.onlyRules == ["force_cast"])
        #expect(config.analyzerRules == ["unused_import"])
        #expect(config.rulesInOnlyAndAnalyzerRules.isEmpty)
    }

    @Test("an analyzer rule already in only_rules is not listed a second time")
    func enableAnalyzerAlreadyInOnlyRules() {
        var config = config(only: ["force_cast", "unused_import"])
        config.enableRule("unused_import", kind: .analyzer)
        #expect(config.analyzerRules == nil)
        #expect(config.onlyRules == ["force_cast", "unused_import"])
    }

    @Test("in only mode a rule analyzer_rules already runs is not listed a second time")
    func enableRuleAlreadyInAnalyzerRules() {
        var config = config(only: ["force_cast"], analyzer: ["line_length"])
        config.enableRule("line_length", kind: .standard)
        #expect(config.onlyRules == ["force_cast"])
        #expect(ConfigRuleListsProblem(config) == nil)
    }

    @Test("enabling a rule already in only_rules changes nothing")
    func enableIsIdempotentInOnlyMode() {
        var config = config(only: ["force_cast", "empty_count"])
        config.enableRule("empty_count", kind: .optIn)
        #expect(config == self.config(only: ["force_cast", "empty_count"]))
    }

    @Test("without only_rules each kind goes to its own list")
    func enableInDefaultMode() {
        var config = config(disabled: ["line_length"])
        config.enableRule("empty_count", kind: .optIn)
        config.enableRule("unused_import", kind: .analyzer)
        config.enableRule("line_length", kind: .standard)
        #expect(config.optInRules == ["empty_count"])
        #expect(config.analyzerRules == ["unused_import"])
        #expect(config.disabledRules == nil)
        #expect(config.onlyRules == nil)
    }

    @Test("an empty only_rules is default mode, so enabling doesn't turn it into a one-rule allowlist")
    func enableUnderEmptyOnlyRules() {
        var config = config(only: [], disabled: ["todo"])
        config.enableRule("empty_count", kind: .optIn)
        #expect(config.onlyRules?.isEmpty == true)
        #expect(config.optInRules == ["empty_count"])
        #expect(!config.hasOnlyRulesConflict)
    }

    // MARK: - Disabling

    @Test("in only mode a standard rule leaves only_rules and never enters disabled_rules")
    func disableStandardInOnlyMode() throws {
        var config = config(only: ["force_cast", "line_length"])
        try config.disableRule("line_length", kind: .standard)
        #expect(config.onlyRules == ["force_cast"])
        #expect(config.disabledRules == nil)
    }

    @Test("in only mode opt-in and analyzer rules leave their lists")
    func disableOptInAndAnalyzerInOnlyMode() throws {
        var config = config(only: ["force_cast", "empty_count"], analyzer: ["unused_import"])
        try config.disableRule("empty_count", kind: .optIn)
        try config.disableRule("unused_import", kind: .analyzer)
        #expect(config.onlyRules == ["force_cast"])
        #expect(config.analyzerRules == nil)
        #expect(config.optInRules == nil)
    }

    @Test("under an empty only_rules, which is default mode, a standard rule goes into disabled_rules")
    func disableUnderEmptyOnlyRules() throws {
        var config = config(only: [])
        try config.disableRule("line_length", kind: .standard)
        #expect(config.disabledRules == ["line_length"])
    }

    @Test("turning off the last only_rules entry is refused rather than switching to the default rules")
    func disableLastOnlyRuleThrows() {
        var config = config(only: ["force_cast"], analyzer: ["unused_import"])
        #expect(throws: YAMLConfigError.self) {
            try config.disableRule("force_cast", kind: .standard)
        }
        #expect(config.onlyRules == ["force_cast"])
    }

    @Test("a batch that would empty only_rules is refused whole, whatever order it comes in")
    func disableBatchEmptyingOnlyRulesThrows() {
        for order in [["a", "b"], ["b", "a"]] {
            var config = config(only: ["a", "b"])
            #expect(throws: YAMLConfigError.self) {
                try config.disableRules(order) { _ in .standard }
            }
            #expect(config.onlyRules == ["a", "b"])
            #expect(config.disabledRules == nil)
        }
    }

    @Test("a batch that leaves something in only_rules goes through")
    func disableBatchInOnlyMode() throws {
        var config = config(only: ["a", "b", "c"])
        try config.disableRules(["a", "c"]) { _ in .standard }
        #expect(config.onlyRules == ["b"])
        #expect(config.disabledRules == nil)
    }

    @Test("without only_rules a standard rule goes into disabled_rules and opt-in rules leave theirs")
    func disableInDefaultMode() throws {
        var config = config(optIn: ["empty_count"], analyzer: ["unused_import"])
        try config.disableRules(["line_length", "empty_count", "unused_import"]) { id in
            switch id {
            case "empty_count": .optIn
            case "unused_import": .analyzer
            default: .standard
            }
        }
        #expect(config.disabledRules == ["line_length"])
        #expect(config.optInRules == nil)
        #expect(config.analyzerRules == nil)
    }
}

extension YAMLConfigurationEngine.YAMLConfig {
    /// A configuration holding just these rule lists, for the rule-list tests.
    static func ruleLists(
        only: [String]? = nil,
        optIn: [String]? = nil,
        disabled: [String]? = nil,
        analyzer: [String]? = nil
    ) -> Self {
        var config = Self()
        config.onlyRules = only
        config.optInRules = optIn
        config.disabledRules = disabled
        config.analyzerRules = analyzer
        return config
    }
}
