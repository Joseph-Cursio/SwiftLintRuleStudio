//
//  RuleListItemTests.swift
//  SwiftLintRuleStudioTests
//
//  Accessibility regression for P1.5: a rule that is neither enabled nor opt-in
//  showed only a gray status dot with no accompanying text, so its state was
//  conveyed by color alone. Every state must now carry a text label.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct RuleListItemTests {
    private func makeRule(isEnabled: Bool, isOptIn: Bool) -> Rule {
        Rule(
            id: "some_rule", name: "Some Rule", description: "A rule.",
            category: .style, isOptIn: isOptIn, severity: .warning, parameters: nil,
            triggeringExamples: [], nonTriggeringExamples: [], documentation: nil,
            isEnabled: isEnabled, supportsAutocorrection: false
        )
    }

    @Test("A disabled (not opt-in) rule shows a 'Disabled' status label")
    func testDisabledRuleShowsLabel() throws {
        let view = RuleListItem(rule: makeRule(isEnabled: false, isOptIn: false))
        #expect(throws: Never.self) {
            try view.inspect().find(text: "Disabled")
        }
    }

    @Test("An enabled rule does not show the 'Disabled' label")
    func testEnabledRuleHidesLabel() throws {
        let view = RuleListItem(rule: makeRule(isEnabled: true, isOptIn: false))
        let hasDisabled = (try? view.inspect().find(text: "Disabled")) != nil
        #expect(hasDisabled == false)
        // Sanity: the enabled state still carries its own text.
        #expect(throws: Never.self) {
            try view.inspect().find(text: "Enabled")
        }
    }

    @Test("An opt-in disabled rule shows 'Opt-In', not 'Disabled'")
    func testOptInRuleShowsOptInNotDisabled() throws {
        let view = RuleListItem(rule: makeRule(isEnabled: false, isOptIn: true))
        let hasDisabled = (try? view.inspect().find(text: "Disabled")) != nil
        #expect(hasDisabled == false)
        #expect(throws: Never.self) {
            try view.inspect().find(text: "Opt-In")
        }
    }
}
