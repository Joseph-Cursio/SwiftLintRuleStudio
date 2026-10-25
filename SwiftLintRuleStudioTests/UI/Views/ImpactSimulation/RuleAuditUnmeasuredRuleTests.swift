//
//  RuleAuditUnmeasuredRuleTests.swift
//  SwiftLintRuleStudioTests
//
//  Rules the audit could not measure — a failed simulation, an analyzer rule linting never
//  runs, a SourceKit rule where SourceKit can't load — must never pass for safe. The audit
//  once clamped a failure's -1 to 0, showed every such rule as "Safe to enable", and "Enable
//  all safe rules" switched them all on.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite("Rule audit: rules with no violation count")
struct RuleAuditUnmeasuredRuleTests {

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

    private static func measuredResult(_ identifier: String, violationCount: Int) -> RuleImpactResult {
        RuleImpactResult(
            ruleId: identifier,
            violationCount: violationCount,
            violations: [],
            affectedFiles: [],
            simulationDuration: 0.1
        )
    }

    private static func disabledEntry(_ result: RuleImpactResult) -> RuleAuditEntry {
        RuleAuditEntry(rule: makeRule(result.ruleId), impactResult: result, isCurrentlyEnabled: false)
    }

    private static func failedEntry(_ identifier: String, reason: String? = "Invalid configuration") -> RuleAuditEntry {
        disabledEntry(.failed(ruleId: identifier, reason: reason))
    }

    private static func analyzerEntry(_ identifier: String) -> RuleAuditEntry {
        disabledEntry(.unmeasurable(ruleId: identifier, reason: .analyzerRule))
    }

    private static func makeRow(_ entry: RuleAuditEntry, isExpanded: Bool = false) -> RuleAuditRow {
        RuleAuditRow(
            entry: entry,
            isExpanded: isExpanded,
            isSelected: false,
            totalSwiftFiles: 10,
            maxViolationCount: 10,
            onToggleExpand: {},
            onToggleSelect: {},
            onEnable: {}
        )
    }

    // MARK: - RuleAuditEntry

    @Test("A failed simulation has no violation or file count and is a failure, not safe")
    func failedEntryHasNoCount() {
        let entry = Self.failedEntry("broken")

        #expect(entry.violationCount == nil)
        #expect(entry.affectedFileCount == nil, "0 files would read as clean")
        #expect(entry.effortCategory == .failed)
        #expect(entry.unmeasuredExplanation == "Invalid configuration")
    }

    @Test("A result carrying the old -1 failure count is not clamped to 0 violations")
    func legacyFailureCountIsNotClamped() {
        // Built the way the simulator used to report a failure. `max(count, 0)` turned this
        // into 0 — "Safe to enable".
        let entry = Self.disabledEntry(Self.measuredResult("broken", violationCount: -1))

        #expect(entry.violationCount == nil)
        #expect(entry.effortCategory == .failed)
        #expect(RuleAuditView.safeDisabledRuleIds(in: [entry]).isEmpty)
    }

    @Test("An analyzer rule has no violation count and can't be measured")
    func analyzerEntryIsUnmeasurable() throws {
        let entry = Self.analyzerEntry("unused_import")

        #expect(entry.violationCount == nil)
        #expect(entry.effortCategory == .unmeasurable)
        let explanation = try #require(entry.unmeasuredExplanation)
        #expect(explanation.contains("swiftlint analyze"))
    }

    @Test("A disabled rule with no result at all is not safe")
    func disabledEntryWithoutResultIsNotSafe() {
        let entry = RuleAuditEntry(rule: Self.makeRule("lost"), impactResult: nil, isCurrentlyEnabled: false)

        #expect(entry.violationCount == nil)
        #expect(entry.effortCategory == .failed)
    }

    @Test("A measured rule keeps its count and effort category")
    func measuredEntryKeepsItsCount() {
        let clean = Self.disabledEntry(Self.measuredResult("clean", violationCount: 0))
        let noisy = Self.disabledEntry(Self.measuredResult("noisy", violationCount: 7))

        #expect(clean.violationCount == 0)
        #expect(clean.effortCategory == .safe)
        #expect(clean.unmeasuredExplanation == nil)
        #expect(noisy.violationCount == 7)
        #expect(noisy.effortCategory == .moderate)
    }

    // MARK: - EffortCategory

    @Test("A negative count is a failure, neither safe nor high effort")
    func negativeCountIsAFailure() {
        #expect(EffortCategory(violationCount: -1) == .failed)
        #expect(EffortCategory(violationCount: -50) == .failed)
    }

    // MARK: - Enable all safe rules

    @Test("Enable all safe rules picks only rules measured with no violations")
    func safeSelectionSkipsUnmeasuredRules() {
        let entries = [
            Self.disabledEntry(Self.measuredResult("clean", violationCount: 0)),
            Self.disabledEntry(Self.measuredResult("noisy", violationCount: 4)),
            Self.failedEntry("broken"),
            Self.failedEntry("broken_without_reason", reason: nil),
            Self.analyzerEntry("unused_import"),
            Self.disabledEntry(.unmeasurable(ruleId: "sourcekit_rule", reason: .sourceKitUnavailable))
        ]

        #expect(RuleAuditView.safeDisabledRuleIds(in: entries) == ["clean"])
    }

    // MARK: - AuditSummary

    @Test("The summary counts failed and unmeasurable rules apart from the safe ones")
    func summaryCountsUnmeasuredApart() {
        let entries = [
            Self.disabledEntry(Self.measuredResult("clean", violationCount: 0)),
            Self.disabledEntry(Self.measuredResult("noisy", violationCount: 3)),
            Self.failedEntry("broken_one"),
            Self.failedEntry("broken_two"),
            Self.analyzerEntry("unused_import")
        ]

        let summary = AuditSummary(entries: entries, totalSwiftFiles: 5, auditDuration: 1)

        #expect(summary.safeCount == 1)
        #expect(summary.lowCount == 1)
        #expect(summary.failedCount == 2)
        #expect(summary.unmeasurableCount == 1)
        #expect(summary.totalRulesTested == 5)
    }

    // MARK: - Ordering

    @Test("Rules with no count sort below every measured rule, never among the safe ones")
    func buildAuditEntriesSortsUnmeasuredLast() {
        let results: [RuleImpactResult] = [
            .failed(ruleId: "broken", reason: "boom"),
            Self.measuredResult("noisy", violationCount: 30),
            .unmeasurable(ruleId: "unused_import", reason: .analyzerRule),
            Self.measuredResult("clean", violationCount: 0)
        ]
        let enabled = Self.makeRule("already_on")

        let entries = RuleAuditView.buildAuditEntries(
            disabledResults: results,
            enabledRules: [enabled],
            allRules: results.map { Self.makeRule($0.ruleId) } + [enabled]
        )

        #expect(entries.prefix(2).map(\.id) == ["clean", "noisy"])
        #expect(Set(entries.dropFirst(2).prefix(2).map(\.id)) == ["broken", "unused_import"])
        #expect(entries.last?.id == "already_on")
    }

    @Test("Sorting by violations puts rules with no count last in either direction")
    func violationOrderPutsUnmeasuredLast() {
        let measured = Self.disabledEntry(Self.measuredResult("noisy", violationCount: 9))
        let failed = Self.failedEntry("broken")

        #expect(RuleAuditEntry.isOrderedByViolations(measured, failed, ascending: true))
        #expect(RuleAuditEntry.isOrderedByViolations(measured, failed, ascending: false))
        #expect(!RuleAuditEntry.isOrderedByViolations(failed, measured, ascending: true))
        #expect(!RuleAuditEntry.isOrderedByViolations(failed, measured, ascending: false))
    }

    @Test("Sorting by violations keeps every disabled rule, even one with no count, above the enabled ones")
    func violationOrderSplitsEnabledFirst() {
        // After a Name or Category sort, a violations sort used to scatter failed rows
        // among the enabled ones.
        let failed = Self.failedEntry("broken")
        let enabledFromAudit = RuleAuditEntry(
            rule: Self.makeRule("turned_on"),
            impactResult: Self.measuredResult("turned_on", violationCount: 0),
            isCurrentlyEnabled: true
        )
        let enabledBefore = RuleAuditEntry(
            rule: Self.makeRule("already_on"),
            impactResult: nil,
            isCurrentlyEnabled: true
        )

        for ascending in [true, false] {
            var entries = [enabledBefore, enabledFromAudit, failed]
            entries.sort { RuleAuditEntry.isOrderedByViolations($0, $1, ascending: ascending) }
            #expect(entries.first?.id == "broken", "ascending: \(ascending)")
        }
    }

    // MARK: - Row

    @Test("A failed row's accessibility label says it failed and why, with no violation count")
    func failedRowLabelGivesTheReason() {
        let row = Self.makeRow(Self.failedEntry("broken", reason: "Invalid configuration"))

        let matchesFailureLabel: (InspectableView<ViewType.ClassifiedView>) throws -> Bool = { view in
            guard let label = try? view.accessibilityLabel().string() else { return false }
            return label.contains("broken")
                && label.contains("Simulation failed")
                && label.contains("Invalid configuration")
                && !label.contains("violations")
        }

        #expect((try? row.inspect().find(where: matchesFailureLabel)) != nil)
    }

    @Test("A SourceKit rule's label explains once why it has no count")
    func sourceKitRowLabelDoesNotRepeatItself() {
        let entry = Self.disabledEntry(.unmeasurable(ruleId: "sk_rule", reason: .sourceKitUnavailable))

        let label = RuleAuditRow.accessibilityLabel(for: entry, isUnavailable: true)

        #expect(label.contains("depends on SourceKit"))
        #expect(!label.contains("not checked in this app"), "the explanation already says it")
    }

    @Test("A SourceKit rule with a count still says it isn't checked in this app")
    func measuredUnavailableRowLabelKeepsTheNote() {
        let entry = Self.disabledEntry(Self.measuredResult("sk_rule", violationCount: 0))

        let label = RuleAuditRow.accessibilityLabel(for: entry, isUnavailable: true)

        #expect(label.contains("not checked in this app"))
    }

    @Test("A rule enabled from the audit shows a dash, not the count it was enabled with")
    func enabledRowShowsDash() {
        let entry = RuleAuditEntry(
            rule: Self.makeRule("turned_on"),
            impactResult: Self.measuredResult("turned_on", violationCount: 5),
            isCurrentlyEnabled: true
        )
        let row = Self.makeRow(entry)

        // "enabled" is the control: it shows the row was inspected at all.
        #expect((try? row.inspect().find(text: "enabled")) != nil)
        #expect((try? row.inspect().find(text: "5")) == nil)
    }

    @Test("An unmeasured row's detail panel explains why instead of a file breakdown")
    func unmeasuredRowDetailExplains() {
        let row = Self.makeRow(Self.analyzerEntry("unused_import"), isExpanded: true)
        let detail = row.expandedDetail

        #expect((try? detail.inspect().find(text: "Can't be measured here")) != nil)
        #expect((try? detail.inspect().find(text: "File Breakdown")) == nil)
    }
}
