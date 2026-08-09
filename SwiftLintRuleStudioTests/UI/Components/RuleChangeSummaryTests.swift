//
//  RuleChangeSummaryTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for the added/removed/modified summary shared by the import and
//  migration previews.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite("RuleChangeSummary")
struct RuleChangeSummaryTests {

    // MARK: - Fixtures

    private static func makeDiff(
        added: [String] = [],
        removed: [String] = [],
        modified: [String] = []
    ) -> YAMLConfigurationEngine.ConfigDiff {
        YAMLConfigurationEngine.ConfigDiff(
            addedRules: added,
            removedRules: removed,
            modifiedRules: modified,
            before: "",
            after: ""
        )
    }

    private static func summaryContains(
        _ diff: YAMLConfigurationEngine.ConfigDiff,
        text: String
    ) -> Bool {
        (try? RuleChangeSummary(diff: diff).inspect().find(text: text)) != nil
    }

    // MARK: - Each section appears only when it has content

    @Test("Added rules are summarised with a count")
    func showsAddedRules() {
        let diff = Self.makeDiff(added: ["force_cast", "line_length"])

        #expect(Self.summaryContains(diff, text: "2 rule(s) to add"))
    }

    @Test("Removed rules are summarised with a count")
    func showsRemovedRules() {
        let diff = Self.makeDiff(removed: ["todo"])

        #expect(Self.summaryContains(diff, text: "1 rule(s) to remove"))
    }

    @Test("Modified rules are summarised with a count")
    func showsModifiedRules() {
        let diff = Self.makeDiff(modified: ["line_length", "type_body_length", "file_length"])

        #expect(Self.summaryContains(diff, text: "3 rule(s) to modify"))
    }

    @Test("A section with nothing in it is not rendered")
    func hidesEmptySections() {
        // Only additions — the other two rows must be absent rather than
        // rendered as "0 rule(s) to remove".
        let diff = Self.makeDiff(added: ["force_cast"])

        #expect(Self.summaryContains(diff, text: "1 rule(s) to add"))
        #expect(!Self.summaryContains(diff, text: "0 rule(s) to remove"))
        #expect(!Self.summaryContains(diff, text: "0 rule(s) to modify"))
    }

    @Test("Each section is independent of the others")
    func sectionsAreIndependent() {
        #expect(!Self.summaryContains(Self.makeDiff(removed: ["a"]), text: "1 rule(s) to add"))
        #expect(!Self.summaryContains(Self.makeDiff(added: ["a"]), text: "1 rule(s) to remove"))
        #expect(!Self.summaryContains(Self.makeDiff(added: ["a"]), text: "1 rule(s) to modify"))
    }

    // MARK: - Combinations

    @Test("All three kinds of change are summarised together")
    func showsAllThreeSections() {
        let diff = Self.makeDiff(
            added: ["a_one", "a_two"],
            removed: ["r_one"],
            modified: ["m_one", "m_two", "m_three"]
        )

        #expect(Self.summaryContains(diff, text: "2 rule(s) to add"))
        #expect(Self.summaryContains(diff, text: "1 rule(s) to remove"))
        #expect(Self.summaryContains(diff, text: "3 rule(s) to modify"))
    }

    @Test("A diff with no changes renders nothing")
    func rendersNothingForAnEmptyDiff() throws {
        let diff = Self.makeDiff()

        #expect(!diff.hasChanges, "sanity: this fixture is the no-change case")

        let texts = try RuleChangeSummary(diff: diff).inspect().findAll(ViewType.Text.self)
        #expect(texts.isEmpty)
    }

    // MARK: - Counts

    @Test("The count reflects how many rules changed, not which")
    func countsRulesNotContent() {
        let many = (1...12).map { "rule_\($0)" }
        let diff = Self.makeDiff(added: many)

        #expect(Self.summaryContains(diff, text: "12 rule(s) to add"))
    }

    @Test("Duplicate entries are counted as the list reports them")
    func countsDuplicatesAsListed() {
        // The view is a faithful readout of the diff; de-duplication, if it is
        // ever wanted, belongs in the diff rather than here.
        let diff = Self.makeDiff(added: ["force_cast", "force_cast"])

        #expect(Self.summaryContains(diff, text: "2 rule(s) to add"))
    }

    // MARK: - Accessibility

    @Test("The status icons are hidden from assistive technologies")
    func iconsAreHiddenFromAccessibility() throws {
        // Each row's meaning is carried by its text, so the icon would just be
        // a second, redundant stop.
        let diff = Self.makeDiff(added: ["a"], removed: ["r"], modified: ["m"])

        let images = try RuleChangeSummary(diff: diff).inspect().findAll(ViewType.Image.self)

        #expect(images.count == 3)
        for image in images {
            #expect(try image.accessibilityHidden())
        }
    }
}
