//
//  ConfigChangeSummaryTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  What changes between two configurations, in terms of what SwiftLint does.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct ConfigChangeSummaryTests {
    private func summary(_ before: String, _ after: String) throws -> ConfigChangeSummary {
        ConfigChangeSummary(
            from: try YAMLConfigurationEngine.parse(before),
            to: try YAMLConfigurationEngine.parse(after)
        )
    }

    /// Two real backups of one `.swiftlint.yml`: the later one turns on seven opt-in rules,
    /// and was also re-saved without its comments, blank lines or settings order.
    @Test("Opt-in rules added to opt_in_rules count as turned on; reformatting counts as nothing")
    func optInRulesTurnedOn() throws {
        let before = """
            excluded:
              - .build
              # vendored dependency checkouts
              - .swiftinfer

            line_length:
              warning: 160
              error: 200
              ignores_urls: true

            disabled_rules:
              - todo
            """
        let after = """
            excluded:
              - .build
              - .swiftinfer
            line_length:
              error: 200
              ignores_urls: true
              warning: 160
            disabled_rules:
              - todo
            opt_in_rules:
              - array_init
              - closure_spacing
              - empty_count
            """

        let changes = try summary(before, after)

        #expect(changes == ConfigChangeSummary(turnedOn: ["array_init", "closure_spacing", "empty_count"]))
    }

    @Test("Formatting alone is no change")
    func formattingOnly() throws {
        let before = "excluded:\n- a\n\n# note\nline_length: 120\n"
        let after = "line_length: 120\nexcluded:\n  - a\n"

        #expect(try summary(before, after).isEmpty)
    }

    @Test("disabled_rules turns default rules off and back on")
    func disabledRules() throws {
        let changes = try summary("disabled_rules:\n  - todo\n", "disabled_rules:\n  - force_cast\n")

        #expect(changes.turnedOn == ["todo"])
        #expect(changes.turnedOff == ["force_cast"])
    }

    @Test("Removing an opt-in rule from opt_in_rules turns it off")
    func optInRuleRemoved() throws {
        let changes = try summary("opt_in_rules:\n  - empty_count\n", "excluded:\n  - Pods\n")

        #expect(changes.turnedOff == ["empty_count"])
        #expect(changes.pathChanges == ["Now excluded: Pods"])
    }

    @Test("enabled: false turns a rule off")
    func enabledFalse() throws {
        let changes = try summary("line_length: 120\n", "line_length:\n  enabled: false\n")

        #expect(changes.turnedOff == ["line_length"])
        #expect(changes.settingsChanged.isEmpty, "a rule switched off isn't also reported as reconfigured")
    }

    @Test("Each changed setting gets a line")
    func settingsChanged() throws {
        let changes = try summary(
            "line_length:\n  warning: 160\n  ignores_urls: true\n",
            "line_length:\n  warning: 120\n  error: 200\n  severity: error\n"
        )

        #expect(changes.settingsChanged == [
            .init(ruleId: "line_length", details: [
                "severity: default → error",
                "error: set to 200",
                "ignores_urls: removed (was true)",
                "warning: 160 → 120"
            ])
        ])
        #expect(changes.turnedOn.isEmpty && changes.turnedOff.isEmpty)
    }

    @Test("Path changes say what's newly excluded or included, and what no longer is")
    func paths() throws {
        let changes = try summary(
            "excluded:\n  - Pods\n  - Tests\nincluded:\n  - Sources\n  - App\n",
            "excluded:\n  - Pods\n  - Carthage\nincluded:\n  - Sources\n  - Tools\n"
        )

        #expect(changes.pathChanges == [
            "Now excluded: Carthage",
            "No longer excluded: Tests",
            "Now included: Tools",
            "No longer included: App"
        ])
    }

    @Test("Adding included limits linting to it; removing it lints everything again")
    func includedAddedOrRemoved() throws {
        #expect(try summary("reporter: xcode\n", "reporter: xcode\nincluded:\n  - Sources\n").pathChanges
            == ["Only these paths are linted now: Sources"])
        #expect(try summary("included:\n  - Sources\n", "excluded:\n  - Pods\n").pathChanges
            == ["Now excluded: Pods", "included removed: every path is linted again"])
    }

    @Test("disabled_rules wins over opt_in_rules, as it does in SwiftLint")
    func disabledWinsOverOptIn() throws {
        let changes = try summary(
            "opt_in_rules:\n  - empty_count\n",
            "opt_in_rules:\n  - empty_count\ndisabled_rules:\n  - empty_count\n"
        )

        #expect(changes.turnedOff == ["empty_count"])
    }

    @Test("Adding only_rules gets a note, since it turns off rules neither config names")
    func onlyRulesAdded() throws {
        let changes = try summary("opt_in_rules:\n  - empty_count\n", "only_rules:\n  - force_cast\n  - todo\n")

        #expect(changes.turnedOff == ["empty_count"])
        #expect(changes.otherChanges == ["only_rules added: only the 2 rules it lists run now"])
    }

    @Test("Settings the app doesn't model are still reported")
    func passthroughSettings() throws {
        let changes = try summary(
            "warning_threshold: 10\nreporter: xcode\n",
            "warning_threshold: 5\nreporter: json\ncustom_rules:\n  no_print:\n    regex: print\n"
        )

        #expect(changes.otherChanges == [
            "reporter: xcode → json",
            "custom_rules added",
            "warning_threshold: 10 → 5"
        ])
    }

    @Test("A diff built from two configs carries the summary, and counts as a change")
    func diffCarriesSummary() throws {
        let before = try YAMLConfigurationEngine.parse("excluded:\n  - Pods\n")
        var after = before
        after.optInRules = ["empty_count"]

        let diff = YAMLConfigurationEngine.diff(from: before, to: after)

        #expect(diff.addedRules.isEmpty, "the per-rule settings blocks didn't change")
        #expect(diff.changes?.turnedOn == ["empty_count"])
        #expect(diff.hasChanges)
    }

    @Test("Under only_rules, analyzer_rules still run")
    func analyzerRulesUnderOnlyRules() throws {
        let changes = try summary(
            "only_rules:\n  - force_cast\n",
            "only_rules:\n  - force_cast\nanalyzer_rules:\n  - unused_import\n"
        )

        #expect(changes.turnedOn == ["unused_import"])
    }

    @Test("An empty only_rules is no only_rules")
    func emptyOnlyRules() throws {
        let changes = try summary("disabled_rules:\n  - todo\n", "only_rules: []\n")

        #expect(changes.turnedOn == ["todo"])
        #expect(changes.otherChanges.isEmpty)
    }

    @Test("Renamed rules and the old enabled_rules key count as the same thing", arguments: [
        ("disabled_rules:\n  - variable_name\n", "disabled_rules:\n  - identifier_name\n"),
        ("enabled_rules:\n  - empty_count\n", "opt_in_rules:\n  - empty_count\n")
    ])
    func deprecatedNames(before: String, after: String) throws {
        #expect(try summary(before, after).isEmpty)
    }

    @Test("all under opt_in_rules gets a note, not a rule named all")
    func allOptInRules() throws {
        let changes = try summary("opt_in_rules:\n  - empty_count\n", "opt_in_rules:\n  - all\n")

        #expect(changes.turnedOn.isEmpty && changes.turnedOff.isEmpty)
        #expect(changes.otherChanges == ["opt_in_rules: all — every opt-in rule runs now"])
    }

    @Test("The rule catalog settles whether a rule is opt-in")
    func catalogSettlesOptIn() throws {
        // force_unwrapping is opt-in, so listing it under disabled_rules never did anything.
        let before = try YAMLConfigurationEngine.parse("disabled_rules:\n  - force_unwrapping\n")
        let after = try YAMLConfigurationEngine.parse("excluded:\n  - Pods\n")
        let catalog = [Rule(id: "force_unwrapping", name: "", description: "", category: .lint, isOptIn: true)]

        #expect(ConfigChangeSummary(from: before, to: after).turnedOn == ["force_unwrapping"], "a guess without it")
        #expect(ConfigChangeSummary(from: before, to: after, knownRules: catalog).turnedOn.isEmpty)
    }

    @Test("A diff can be summarized again with the catalog")
    func diffKnowingCatalog() throws {
        let before = try YAMLConfigurationEngine.parse("disabled_rules:\n  - force_unwrapping\n")
        let after = try YAMLConfigurationEngine.parse("excluded:\n  - Pods\n")
        let catalog = [Rule(id: "force_unwrapping", name: "", description: "", category: .lint, isOptIn: true)]

        let diff = YAMLConfigurationEngine.diff(from: before, to: after)

        #expect(diff.changes?.turnedOn == ["force_unwrapping"])
        #expect(diff.knowing(catalog).changes?.turnedOn.isEmpty == true)
        #expect(diff.knowing(catalog).changes?.pathChanges == ["Now excluded: Pods"])
    }

    @Test("A diff summarizes what's written, not settings the serializer drops")
    func diffSummarizesWrittenText() throws {
        let current = try YAMLConfigurationEngine.parse("opt_in_rules:\n  - empty_count\n")
        var proposed = current
        // What bulk-disable does to an opt-in rule that's already off.
        proposed.rules["force_unwrapping"] = RuleConfiguration(enabled: false)

        let diff = YAMLConfigurationEngine.diff(from: current, to: proposed)

        #expect(diff.before == diff.after)
        #expect(diff.changes?.isEmpty == true)
    }
}
