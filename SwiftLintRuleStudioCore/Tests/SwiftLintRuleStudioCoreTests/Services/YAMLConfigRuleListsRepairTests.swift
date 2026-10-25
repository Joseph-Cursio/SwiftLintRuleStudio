//
//  YAMLConfigRuleListsRepairTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The repair of a file SwiftLint rejects (issue #83), reading the rule lists the way
//  SwiftLint reads them, and the save that refuses a rejected file.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct YAMLConfigRuleListsRepairTests {

    private func config(
        only: [String]? = nil,
        optIn: [String]? = nil,
        disabled: [String]? = nil,
        analyzer: [String]? = nil
    ) -> YAMLConfigurationEngine.YAMLConfig {
        .ruleLists(only: only, optIn: optIn, disabled: disabled, analyzer: analyzer)
    }

    // MARK: - Repair

    @Test("a file without only_rules is left alone")
    func normalizeLeavesDefaultModeAlone() {
        let original = config(only: [], optIn: ["empty_count"], disabled: ["todo"], analyzer: ["unused_import"])
        #expect(original.normalizedRuleLists() == original)
    }

    @Test("an accepted only-mode file is left alone")
    func normalizeLeavesAcceptedFileAlone() {
        let original = config(only: ["force_cast"], optIn: [], analyzer: ["unused_import"])
        #expect(original.normalizedRuleLists() == original)
    }

    @Test("the issue #83 shape: opt-in rules duplicated into only_rules, analyzer rules in both")
    func normalizeTheIssueShape() {
        let broken = config(
            only: ["trailing_comma", "capture_variable", "array_init", "explicit_self", "unused_import"],
            optIn: ["array_init"],
            analyzer: ["capture_variable", "explicit_self", "unused_import"]
        )
        let repaired = broken.normalizedRuleLists()
        #expect(repaired.onlyRules == ["trailing_comma", "array_init"])
        #expect(repaired.optInRules == nil)
        #expect(repaired.analyzerRules == ["capture_variable", "explicit_self", "unused_import"])
        #expect(!repaired.hasOnlyRulesConflict)
        #expect(repaired.rulesInOnlyAndAnalyzerRules.isEmpty)
    }

    @Test("the fold recovers what the old Rule Browser meant: enabled opt-ins join, disabled rules leave")
    func normalizeFoldsOptInAndDisabled() {
        let broken = config(only: ["force_cast", "line_length"], optIn: ["empty_count"], disabled: ["line_length"])
        let repaired = broken.normalizedRuleLists()
        #expect(repaired.onlyRules == ["force_cast", "empty_count"])
        #expect(repaired.optInRules == nil)
        #expect(repaired.disabledRules == nil)
    }

    @Test("a disabled analyzer rule leaves analyzer_rules too, or it would keep running")
    func normalizeSubtractsDisabledAnalyzers() {
        let repaired = config(
            only: ["force_cast"],
            disabled: ["unused_import"],
            analyzer: ["unused_import", "explicit_self"]
        ).normalizedRuleLists()
        #expect(repaired.analyzerRules == ["explicit_self"])
    }

    @Test("when every listed rule is disabled, only_rules is kept rather than emptied")
    func normalizeNeverEmptiesOnlyRules() {
        let repaired = config(only: ["force_cast"], optIn: ["empty_count"], disabled: ["force_cast", "empty_count"])
            .normalizedRuleLists()
        #expect(repaired.onlyRules == ["force_cast"])
        #expect(repaired.optInRules == nil)
        #expect(repaired.disabledRules == nil)
    }

    @Test("all is not carried into only_rules, where SwiftLint reads it as an unknown rule")
    func normalizeDropsAll() {
        let repaired = config(only: ["force_cast"], optIn: ["all", "empty_count"]).normalizedRuleLists()
        #expect(repaired.onlyRules == ["force_cast", "empty_count"])
    }

    @Test("an analyzer rule that is all of only_rules keeps its only_rules entry")
    func normalizeKeepsOnlyRulesNonEmptyWhenDeduplicating() {
        let repaired = config(only: ["unused_import"], analyzer: ["unused_import", "explicit_self"])
            .normalizedRuleLists()
        #expect(repaired.onlyRules == ["unused_import"])
        #expect(repaired.analyzerRules == ["explicit_self"])
    }

    @Test("comments above the dropped lists move above only_rules")
    func normalizeKeepsComments() throws {
        let yaml = """
        # Allowlist
        only_rules:
          - force_cast
        # Opt-ins agreed 2024
        opt_in_rules:
          - empty_count
        """
        let repaired = try YAMLConfigurationEngine.parse(yaml).normalizedRuleLists()
        let text = try YAMLConfigurationEngine.serialize(repaired)
        #expect(text.contains("# Allowlist\n# Opt-ins agreed 2024\nonly_rules:"))
        #expect(!text.contains("opt_in_rules"))
    }

    @Test("repair is idempotent")
    func normalizeIsIdempotent() {
        let samples = [
            config(only: ["a", "u"], optIn: ["b"], disabled: ["a"], analyzer: ["u"]),
            config(only: ["a"], optIn: ["b"], disabled: ["a", "b"]),
            config(only: ["u"], analyzer: ["u"])
        ]
        for sample in samples {
            let once = sample.normalizedRuleLists()
            #expect(once.normalizedRuleLists() == once)
        }
    }

    // MARK: - Reading the lists the way SwiftLint does

    @Test("a single-string rule list is a one-rule list")
    func scalarRuleListsParse() throws {
        let config = try YAMLConfigurationEngine.parse("only_rules: force_cast\nanalyzer_rules: unused_import\n")
        #expect(config.onlyRules == ["force_cast"])
        #expect(config.analyzerRules == ["unused_import"])
        #expect(config.usesOnlyRules)
    }

    @Test("a single-string included or excluded is a one-path list, and a save keeps it")
    func scalarPathListsParse() throws {
        let config = try YAMLConfigurationEngine.parse("included: Sources\nexcluded: Pods\n")
        #expect(config.included == ["Sources"])
        #expect(config.excluded == ["Pods"])

        let saved = try YAMLConfigurationEngine.parse(YAMLConfigurationEngine.serialize(config))
        #expect(saved.included == ["Sources"])
        #expect(saved.excluded == ["Pods"])
    }

    @Test("enabled_rules is read as opt_in_rules and written back under that name")
    func enabledRulesAlias() throws {
        let yaml = """
        # Extra rules
        enabled_rules:
          - empty_count
        """
        let config = try YAMLConfigurationEngine.parse(yaml)
        #expect(config.optInRules == ["empty_count"])
        let text = try YAMLConfigurationEngine.serialize(config)
        #expect(text.contains("# Extra rules\nopt_in_rules:\n  - empty_count"))
        #expect(!text.contains("enabled_rules"))
    }

    @Test("a rule list with every entry commented out, or ~, is no list, as SwiftLint reads a null")
    func nullRuleListsAreNoList() throws {
        let yaml = """
        only_rules:
          # - force_cast
        opt_in_rules: ~
        disabled_rules:
        analyzer_rules: null
        """
        let config = try YAMLConfigurationEngine.parse(yaml)
        #expect(config.onlyRules == nil)
        #expect(config.optInRules == nil)
        #expect(config.disabledRules == nil)
        #expect(config.analyzerRules == nil)
        #expect(!config.usesOnlyRules)
        #expect(!config.hasOnlyRulesConflict)
        #expect(!(try YAMLConfigurationEngine.serialize(config)).contains("''"))
    }

    @Test("a null opt_in_rules beside only_rules is no conflict, and still shadows enabled_rules")
    func nullOptInRulesBesideOnlyRules() throws {
        let config = try YAMLConfigurationEngine.parse(
            "only_rules:\n  - force_cast\nopt_in_rules:\nenabled_rules:\n  - empty_count\n"
        )
        #expect(config.optInRules == nil)
        #expect(!config.hasOnlyRulesConflict)
    }

    @Test("enabled_rules beside opt_in_rules is ignored by SwiftLint, and kept as written")
    func enabledRulesBesideOptInRulesIsKept() throws {
        let yaml = """
        # legacy list
        enabled_rules:
          - force_unwrapping
        opt_in_rules:
          - empty_count
        """
        let text = try YAMLConfigurationEngine.serialize(YAMLConfigurationEngine.parse(yaml))
        #expect(text.contains("# legacy list\nenabled_rules:\n  - force_unwrapping"))
        #expect(text.contains("opt_in_rules:\n  - empty_count"))
    }

    @Test("enabled_rules beside only_rules is the same conflict")
    func enabledRulesConflict() throws {
        let config = try YAMLConfigurationEngine.parse(
            "only_rules:\n  - force_cast\nenabled_rules:\n  - empty_count\n"
        )
        #expect(config.hasOnlyRulesConflict)
    }

    @Test("opt_in_rules shadows enabled_rules, as in SwiftLint")
    func optInRulesShadowsEnabledRules() throws {
        let config = try YAMLConfigurationEngine.parse(
            "opt_in_rules:\n  - first_where\nenabled_rules:\n  - empty_count\n"
        )
        #expect(config.optInRules == ["first_where"])
    }

    // MARK: - Saving

    @Test("saving a file SwiftLint would reject is refused")
    func saveRefusesConflict() throws {
        let directory = try TestTempDirectory.make("rule-lists-save")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent(".swiftlint.yml")

        #expect(throws: YAMLConfigError.self) {
            try YAMLConfigurationEngine.save(config(only: ["force_cast"], optIn: ["empty_count"]), to: path)
        }
        #expect(!FileManager.default.fileExists(atPath: path.path))

        let repaired = config(only: ["force_cast"], optIn: ["empty_count"]).normalizedRuleLists()
        try YAMLConfigurationEngine.save(repaired, to: path)
        let saved = try YAMLConfigurationEngine.loadConfig(at: path)
        #expect(saved.onlyRules == ["force_cast", "empty_count"])
        #expect(saved.optInRules == nil)
    }
}
