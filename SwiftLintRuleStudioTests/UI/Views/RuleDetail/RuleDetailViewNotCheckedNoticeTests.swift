//
//  RuleDetailViewNotCheckedNoticeTests.swift
//  SwiftLintRuleStudioTests
//
//  The notice under the Enable toggle for a rule this app never checks. Analyzer
//  rules once had none: turning one on and re-running analysis showed no
//  violations, which read as clean code rather than as a rule the app can't run.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing
import ViewInspector

@MainActor
struct RuleDetailViewNotCheckedNoticeTests {
    private func makeRule(isAnalyzer: Bool) -> Rule {
        Rule(
            id: isAnalyzer ? "unused_import" : "force_cast",
            name: isAnalyzer ? "Unused Import" : "Force Cast",
            description: "Test description",
            category: .lint,
            isOptIn: isAnalyzer,
            isAnalyzer: isAnalyzer
        )
    }

    /// The text of the detail view's not-checked notice, or nil when it has none.
    private func noticeText(for rule: Rule) throws -> String? {
        let result = RuleDetailViewTestHelpers.createView(for: rule)
        ViewHosting.expel()
        ViewHosting.host(view: result.view)
        defer { ViewHosting.expel() }
        guard let notice = try? result.view.inspect()
            .find(viewWithAccessibilityIdentifier: "RuleDetailNotCheckedNotice") else {
            return nil
        }
        return try notice.find(ViewType.Text.self).string()
    }

    @Test("An analyzer rule's detail says the app doesn't check it, and why")
    func testAnalyzerRuleShowsNotice() throws {
        let text = try noticeText(for: makeRule(isAnalyzer: true))
        #expect(text == UnmeasurableReason.analyzerRule.notCheckedNotice)
    }

    @Test("A rule the app lints has no not-checked notice")
    func testLintedRuleHasNoNotice() throws {
        #expect(try noticeText(for: makeRule(isAnalyzer: false)) == nil)
    }
}
