//
//  RuleDetailViewParagraphSpacingTests.swift
//  SwiftLintRuleStudioTests
//
//  Paragraphs in a rule's documentation must be separated by an empty line.
//  SwiftUI's Text ignores the HTML paragraph margins, so the gap has to be a real
//  blank line in the text, and not one doubled up next to headings.
//

import AppKit
@testable import SwiftLintRuleStudio
import SwiftUI
import Testing

@MainActor
@Suite("RuleDetailView paragraph spacing")
struct RuleDetailViewParagraphSpacingTests {

    private func html(_ markdown: String) -> String {
        RuleDetailView.convertMarkdownToHTMLForTesting(markdown)
    }

    /// The plain text the detail view ends up drawing, after the same HTML import.
    private func renderedText(_ markdown: String) throws -> String {
        let document = RuleDetailView.wrapHTMLInDocumentForTesting(body: html(markdown), colorScheme: .light)
        let data = try #require(document.data(using: .utf8))
        let attributed = try NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )
        return attributed.string
    }

    @Test("Paragraphs are separated by one empty line")
    func testParagraphsGetAnEmptyLine() throws {
        let text = try renderedText("First paragraph.\n\nSecond paragraph.")
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let first = try #require(lines.firstIndex(of: "First paragraph."))
        #expect(lines[first + 1].isEmpty, "an empty line follows the first paragraph")
        #expect(lines[first + 2] == "Second paragraph.")
    }

    @Test("Lines within a paragraph still flow together")
    func testParagraphLinesFlowTogether() throws {
        let text = try renderedText("One sentence\ncontinued here.")
        #expect(text.contains("One sentence continued here."))
    }

    @Test("Several blank lines between paragraphs give a single gap")
    func testBlankRunsCollapse() {
        let output = html("First.\n\n\n\nSecond.")
        #expect(output.components(separatedBy: "<br><br>").count == 2, "exactly one paragraph break")
        #expect(!output.contains("<br><br>\n<br>"))
    }

    @Test("A blank line after a heading stays a single break")
    func testNoExtraGapAfterHeading() {
        let output = html("## Heading\n\nText under it.")
        #expect(!output.contains("<br><br>"))
        #expect(output.contains("<br>"))
    }

    @Test("A blank line before a heading separates it from the paragraph above")
    func testGapBeforeHeading() {
        #expect(html("Paragraph.\n\n## Heading").contains("<br><br>"))
    }

    @Test("Blank lines at the start or end add nothing")
    func testNoLeadingOrTrailingBreaks() {
        let output = html("\n\nOnly paragraph.\n\n")
        #expect(!output.contains("<br>"))
    }

    @Test("Blank lines inside a code fence are kept as code, not turned into breaks")
    func testBlankLinesInCodeKept() {
        let output = html("```swift\nlet a = 1\n\nlet b = 2\n```")
        #expect(!output.contains("<br>"))
        #expect(output.contains("let a = 1\n\nlet b = 2"))
    }
}
