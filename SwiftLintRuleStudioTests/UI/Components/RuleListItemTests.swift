//
//  RuleListItemTests.swift
//  SwiftLintRuleStudioTests
//
//  Accessibility regression for P1.5: a rule's on/off state was once shown by a
//  coloured dot alone. The row now shows it with a status symbol whose shape
//  differs by state (filled check vs empty circle) and which VoiceOver reads as
//  "Enabled" or "Disabled". Opt-in is a separate, neutral tag.
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

    /// What VoiceOver reads for the row's status symbol.
    private func statusLabel(_ view: RuleListItem) throws -> String {
        try view.inspect()
            .find(viewWithAccessibilityIdentifier: "RuleStatusSymbol")
            .accessibilityLabel()
            .string()
    }

    @Test("An enabled rule's status reads 'Enabled'")
    func testEnabledRuleStatus() throws {
        let view = RuleListItem(rule: makeRule(isEnabled: true, isOptIn: false))
        #expect(try statusLabel(view) == "Enabled")
    }

    @Test("A disabled default rule's status reads 'Disabled'")
    func testDisabledDefaultRuleStatus() throws {
        let view = RuleListItem(rule: makeRule(isEnabled: false, isOptIn: false))
        #expect(try statusLabel(view) == "Disabled")
    }

    @Test("A disabled opt-in rule reads 'Disabled', like any other disabled rule")
    func testDisabledOptInRuleStatus() throws {
        let view = RuleListItem(rule: makeRule(isEnabled: false, isOptIn: true))
        #expect(try statusLabel(view) == "Disabled")
    }

    @Test("An opt-in rule carries the Opt-In tag whether enabled or not")
    func testOptInTag() throws {
        for isEnabled in [true, false] {
            let view = RuleListItem(rule: makeRule(isEnabled: isEnabled, isOptIn: true))
            #expect(throws: Never.self) {
                try view.inspect().find(text: "Opt-In")
            }
        }
    }

    @Test("A default rule has no Opt-In tag")
    func testNoOptInTagForDefaultRule() {
        let view = RuleListItem(rule: makeRule(isEnabled: false, isOptIn: false))
        #expect((try? view.inspect().find(text: "Opt-In")) == nil)
    }

    @Test("State isn't repeated as Enabled/Disabled text under the rule")
    func testNoDuplicateStateText() {
        for isEnabled in [true, false] {
            let view = RuleListItem(rule: makeRule(isEnabled: isEnabled, isOptIn: false))
            #expect((try? view.inspect().find(text: "Enabled")) == nil)
            #expect((try? view.inspect().find(text: "Disabled")) == nil)
        }
    }
}
