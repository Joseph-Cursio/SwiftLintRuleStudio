//
//  RuleBrowserSelectionTests.swift
//  SwiftLintRuleStudioTests
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

/// `RuleBrowserView.selection(_:survivingIn:)`, lifted out of an `onChange` closure no test
/// could fire.
///
/// Three cases, and only one was visible in the closure it came from. The interesting one is the
/// third: it is what keeps the detail pane from showing a rule the list no longer offers.
@MainActor
@Suite("Rule browser selection survives filtering")
struct RuleBrowserSelectionTests {

    private func rule(_ identifier: String) -> Rule {
        Rule(
            id: identifier,
            name: identifier,
            description: "",
            category: .style,
            isOptIn: false,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: true,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: nil
        )
    }

    @Test("Nothing selected stays nothing")
    func noSelectionStaysNil() {
        #expect(RuleBrowserView.selection(nil, survivingIn: [rule("a"), rule("b")]) == nil)
    }

    @Test("A selection the filter still contains survives")
    func survivingSelectionIsKept() {
        let kept = RuleBrowserView.selection("b", survivingIn: [rule("a"), rule("b")])
        #expect(kept == "b")
    }

    @Test("A selection the filter has dropped is cleared")
    func vanishedSelectionIsCleared() {
        #expect(RuleBrowserView.selection("b", survivingIn: [rule("a")]) == nil)
    }

    @Test("An empty filter clears any selection")
    func emptyResultClearsSelection() {
        #expect(RuleBrowserView.selection("a", survivingIn: []) == nil)
    }

    @Test("The result is always absent or present in the rules")
    func resultIsAlwaysReachable() {
        // The law the three cases share: whatever comes back can be shown, because it is either
        // nothing or a rule the list currently offers.
        let rules = [rule("a"), rule("b"), rule("c")]
        for candidate in [nil, "a", "b", "c", "zzz"] as [String?] {
            let result = RuleBrowserView.selection(candidate, survivingIn: rules)
            #expect(result == nil || rules.contains { $0.id == result })
        }
    }
}
