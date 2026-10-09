//
//  PRCommentGeneratorChangeSummaryTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The PR comment for a diff that carries a ConfigChangeSummary.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct PRCommentGeneratorChangeSummaryTests {
    private func diff(_ changes: ConfigChangeSummary) -> YAMLConfigurationEngine.ConfigDiff {
        YAMLConfigurationEngine.ConfigDiff(
            addedRules: [],
            removedRules: [],
            modifiedRules: [],
            before: "before",
            after: "after",
            changes: changes
        )
    }

    @Test("Rules turned on and off, changed settings and paths each get a section")
    func sectionsFromChangeSummary() {
        let markdown = PRCommentGenerator().generateMarkdown(
            from: diff(ConfigChangeSummary(
                turnedOn: ["empty_count"],
                turnedOff: ["todo"],
                settingsChanged: [.init(ruleId: "line_length", details: ["warning: 160 → 120"])],
                pathChanges: ["Now excluded: Pods"]
            )),
            options: PRCommentOptions(includeHeader: false, includeFooter: false, includeRuleLinks: false)
        )

        #expect(markdown.contains("- **1** rule(s) turned on"))
        #expect(markdown.contains("### Rules Turned On (1)\n\n- [+] `empty_count`"))
        #expect(markdown.contains("### Rules Turned Off (1)\n\n- [-] `todo`"))
        #expect(markdown.contains("### Rule Settings Changed (1)\n\n- [~] `line_length`\n  - warning: 160 → 120"))
        #expect(markdown.contains("### Paths\n\n- Now excluded: Pods"))
        #expect(!markdown.contains("Rules Added"))
    }

    @Test("A change summary with nothing in it says SwiftLint checks the same things")
    func emptyChangeSummary() {
        let markdown = PRCommentGenerator().generateMarkdown(from: diff(ConfigChangeSummary()))

        #expect(markdown.contains("*No changes to what SwiftLint checks.*"))
    }

    @Test("The summary lists path and other changes too, so it's never an empty heading")
    func summaryCoversPathsAndOtherChanges() {
        let markdown = PRCommentGenerator().generateMarkdown(
            from: diff(ConfigChangeSummary(
                pathChanges: ["Now excluded: Pods"],
                otherChanges: ["reporter: xcode → json"]
            ))
        )

        #expect(markdown.contains("### Summary\n\n- Paths changed\n- **1** other setting(s) changed\n"))
    }
}
