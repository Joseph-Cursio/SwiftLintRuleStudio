//
//  RuleAuditActionHelpersTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for the collection-shaping helpers in RuleAuditView+Actions:
//  audit entry building and sorting, safe-rule selection, and enabled-flag updates.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
@Suite("RuleAuditView action helpers")
struct RuleAuditActionHelpersTests {

    // MARK: - Fixtures

    private static func makeRule(_ identifier: String) -> Rule {
        Rule(
            id: identifier,
            name: identifier,
            description: "desc for \(identifier)",
            category: .lint,
            isOptIn: false
        )
    }

    private static func makeResult(_ identifier: String, violationCount: Int) -> RuleImpactResult {
        RuleImpactResult(
            ruleId: identifier,
            violationCount: violationCount,
            violations: [],
            affectedFiles: [],
            simulationDuration: 0.1
        )
    }

    private static func makeEntry(
        _ identifier: String,
        violationCount: Int,
        isEnabled: Bool
    ) -> RuleAuditEntry {
        RuleAuditEntry(
            rule: makeRule(identifier),
            impactResult: isEnabled ? nil : makeResult(identifier, violationCount: violationCount),
            isCurrentlyEnabled: isEnabled
        )
    }

    // MARK: - buildAuditEntries

    @Test("Disabled rules become tested entries carrying their impact result")
    func buildsEntriesForDisabledRules() {
        let rule = Self.makeRule("force_cast")
        let result = Self.makeResult("force_cast", violationCount: 12)

        let entries = RuleAuditView.buildAuditEntries(
            disabledResults: [result],
            enabledRules: [],
            allRules: [rule]
        )

        #expect(entries.count == 1)
        #expect(entries[0].id == "force_cast")
        #expect(entries[0].isCurrentlyEnabled == false)
        #expect(entries[0].violationCount == 12)
        #expect(entries[0].impactResult != nil)
    }

    @Test("Enabled rules become greyed-out entries with no impact result")
    func buildsEntriesForEnabledRules() {
        let enabled = Self.makeRule("line_length")

        let entries = RuleAuditView.buildAuditEntries(
            disabledResults: [],
            enabledRules: [enabled],
            allRules: [enabled]
        )

        #expect(entries.count == 1)
        #expect(entries[0].isCurrentlyEnabled)
        #expect(entries[0].impactResult == nil)
    }

    @Test("A result naming a rule absent from allRules is dropped")
    func dropsResultsForUnknownRules() {
        let known = Self.makeRule("known_rule")

        let entries = RuleAuditView.buildAuditEntries(
            disabledResults: [
                Self.makeResult("known_rule", violationCount: 1),
                Self.makeResult("ghost_rule", violationCount: 99)
            ],
            enabledRules: [],
            allRules: [known]
        )

        #expect(entries.map(\.id) == ["known_rule"])
    }

    @Test("Disabled entries sort ahead of enabled ones")
    func sortsDisabledBeforeEnabled() {
        let disabled = Self.makeRule("disabled_rule")
        let enabled = Self.makeRule("enabled_rule")

        let entries = RuleAuditView.buildAuditEntries(
            // A high violation count must still not push the disabled entry below
            // the enabled one — the enabled/disabled split is the primary key.
            disabledResults: [Self.makeResult("disabled_rule", violationCount: 500)],
            enabledRules: [enabled],
            allRules: [disabled, enabled]
        )

        #expect(entries.map(\.id) == ["disabled_rule", "enabled_rule"])
    }

    @Test("Within the disabled group, entries sort by ascending violation count")
    func sortsDisabledByAscendingViolationCount() {
        let rules = ["high", "safe", "mid"].map { Self.makeRule($0) }

        let entries = RuleAuditView.buildAuditEntries(
            disabledResults: [
                Self.makeResult("high", violationCount: 40),
                Self.makeResult("safe", violationCount: 0),
                Self.makeResult("mid", violationCount: 7)
            ],
            enabledRules: [],
            allRules: rules
        )

        #expect(entries.map(\.id) == ["safe", "mid", "high"])
        #expect(entries.map(\.violationCount) == [0, 7, 40])
    }

    @Test("Empty input produces no entries")
    func buildsNoEntriesFromEmptyInput() {
        let entries = RuleAuditView.buildAuditEntries(
            disabledResults: [],
            enabledRules: [],
            allRules: []
        )

        #expect(entries.isEmpty)
    }

    @Test("Duplicate rule ids in allRules do not trap")
    func toleratesDuplicateRuleIds() {
        // The registry should never hand back duplicates, but building the lookup
        // map must not be a crash surface if it ever does.
        let duplicated = [Self.makeRule("dupe"), Self.makeRule("dupe")]

        let entries = RuleAuditView.buildAuditEntries(
            disabledResults: [Self.makeResult("dupe", violationCount: 3)],
            enabledRules: [],
            allRules: duplicated
        )

        #expect(entries.count == 1)
        #expect(entries[0].id == "dupe")
    }

    // MARK: - safeDisabledRuleIds

    @Test("Only disabled rules with zero violations count as safe")
    func selectsOnlySafeDisabledRules() {
        let entries = [
            Self.makeEntry("safe_one", violationCount: 0, isEnabled: false),
            Self.makeEntry("safe_two", violationCount: 0, isEnabled: false),
            Self.makeEntry("has_violations", violationCount: 4, isEnabled: false),
            Self.makeEntry("already_on", violationCount: 0, isEnabled: true)
        ]

        let safeIds = RuleAuditView.safeDisabledRuleIds(in: entries)

        #expect(Set(safeIds) == ["safe_one", "safe_two"])
    }

    @Test("No safe rules yields an empty selection")
    func selectsNothingWhenNoSafeRules() {
        let entries = [
            Self.makeEntry("noisy", violationCount: 30, isEnabled: false),
            Self.makeEntry("already_on", violationCount: 0, isEnabled: true)
        ]

        #expect(RuleAuditView.safeDisabledRuleIds(in: entries).isEmpty)
    }

    @Test("An empty entry list yields an empty selection")
    func selectsNothingFromEmptyEntries() {
        #expect(RuleAuditView.safeDisabledRuleIds(in: []).isEmpty)
    }

    // MARK: - markEntriesEnabled

    @Test("Named entries flip to enabled and keep their impact result")
    func marksNamedEntriesEnabled() {
        let entries = [
            Self.makeEntry("target", violationCount: 5, isEnabled: false),
            Self.makeEntry("untouched", violationCount: 2, isEnabled: false)
        ]

        let updated = RuleAuditView.markEntriesEnabled(in: entries, ruleIds: ["target"])

        #expect(updated[0].isCurrentlyEnabled)
        #expect(updated[0].impactResult != nil, "impact result must survive the flip")
        #expect(updated[0].violationCount == 5)
        #expect(updated[1].isCurrentlyEnabled == false)
    }

    @Test("Marking preserves the original ordering")
    func preservesOrderWhenMarking() {
        let entries = [
            Self.makeEntry("first", violationCount: 9, isEnabled: false),
            Self.makeEntry("second", violationCount: 1, isEnabled: false),
            Self.makeEntry("third", violationCount: 4, isEnabled: false)
        ]

        let updated = RuleAuditView.markEntriesEnabled(in: entries, ruleIds: ["second", "third"])

        #expect(updated.map(\.id) == ["first", "second", "third"])
        #expect(updated.map(\.isCurrentlyEnabled) == [false, true, true])
    }

    @Test("An empty id set leaves every entry unchanged")
    func marksNothingForEmptyIdSet() {
        let entries = [Self.makeEntry("rule", violationCount: 3, isEnabled: false)]

        let updated = RuleAuditView.markEntriesEnabled(in: entries, ruleIds: [])

        #expect(updated[0].isCurrentlyEnabled == false)
    }

    @Test("Ids not present among the entries are ignored")
    func ignoresUnknownIdsWhenMarking() {
        let entries = [Self.makeEntry("rule", violationCount: 3, isEnabled: false)]

        let updated = RuleAuditView.markEntriesEnabled(in: entries, ruleIds: ["not_here"])

        #expect(updated.count == 1)
        #expect(updated[0].isCurrentlyEnabled == false)
    }
}
