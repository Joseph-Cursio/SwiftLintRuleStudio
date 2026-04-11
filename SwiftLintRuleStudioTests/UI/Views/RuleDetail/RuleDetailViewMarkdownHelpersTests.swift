//
//  RuleDetailViewMarkdownHelpersTests.swift
//  SwiftLintRuleStudioTests
//
//  Extended tests for RuleDetailView+MarkdownHelpers covering edge cases
//

import SwiftUI
import Testing
@testable import SwiftLintRuleStudioCore
@testable import SwiftLintRuleStudio

@MainActor
@Suite("RuleDetailView MarkdownHelpers Extended Tests")
struct RuleDetailViewMarkdownHelpersTests {

    // MARK: - processContentForDisplay Tests

    @Test("Strips h1 HTML tag from first line")
    func stripsH1HTMLTag() {
        let content = "<h1>My Rule</h1>\nSome description."
        let processed = RuleDetailView.processContentForDisplayForTesting(content)
        #expect(!processed.contains("<h1>My Rule</h1>"))
        #expect(processed.contains("Some description."))
    }

    @Test("Strips markdown h1 from first line")
    func stripsMarkdownH1() {
        let content = "# My Rule\nSome description."
        let processed = RuleDetailView.processContentForDisplayForTesting(content)
        #expect(!processed.contains("# My Rule"))
        #expect(processed.contains("Some description."))
    }

    @Test("Strips metadata lines with bold markers")
    func stripsMetadataLines() {
        let content = """
        # Rule Name
        * **Severity**: warning
        * **Category**: lint
        * **Default configuration**: See below

        ## Examples
        Some examples.
        """
        let processed = RuleDetailView.processContentForDisplayForTesting(content)
        #expect(!processed.contains("Severity"))
        #expect(!processed.contains("Category"))
        #expect(processed.contains("Examples"))
    }

    @Test("Strips HTML table after default configuration metadata")
    func stripsHTMLTable() {
        // The colon must be outside the bold markers for isDefaultConfigLine to match
        let content = """
        * **Default configuration:** See below
        <table>
        <thead><tr><th>Key</th><th>Value</th></tr></thead>
        <tbody><tr><td>severity</td><td>warning</td></tr></tbody>
        </table>
        ## Examples
        Code here.
        """
        let processed = RuleDetailView.processContentForDisplayForTesting(content)
        // The metadata line is stripped, and the table is skipped
        #expect(!processed.contains("<table>"))
        #expect(!processed.contains("<thead>"))
        #expect(!processed.contains("<tbody>"))
        #expect(!processed.contains("</table>"))
        #expect(processed.contains("Examples"))
    }

    @Test("Strips rationale section content")
    func stripsRationaleSection() {
        let content = """
        ## Rationale
        This explains why the rule exists.
        It has multiple lines.

        ## Examples
        Some example code.
        """
        let processed = RuleDetailView.processContentForDisplayForTesting(content)
        #expect(!processed.contains("Rationale"))
        #expect(!processed.contains("This explains why"))
        #expect(processed.contains("Examples"))
    }

    @Test("Stops stripping rationale at next heading")
    func stopsStrippingAtNextHeading() {
        let content = """
        ## Why This Matters
        Important rationale text.
        ## Non Triggering Examples
        let value = 42
        """
        let processed = RuleDetailView.processContentForDisplayForTesting(content)
        #expect(!processed.contains("Important rationale text"))
        #expect(processed.contains("Non Triggering Examples"))
    }

    @Test("Adds blank line before Non Triggering Examples")
    func addsBlankBeforeNonTriggeringExamples() {
        let content = """
        ## Triggering Examples
        bad code
        ## Non Triggering Examples
        good code
        """
        let processed = RuleDetailView.processContentForDisplayForTesting(content)
        // The blank line is added before "## Non"
        let lines = processed.components(separatedBy: .newlines)
        if let nonIdx = lines.firstIndex(where: { $0.contains("## Non") }) {
            #expect(nonIdx > 0)
            #expect(lines[nonIdx - 1].trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - convertMarkdownToHTML Tests

    @Test("Converts h1 markdown to HTML")
    func convertsH1() {
        let html = RuleDetailView.convertMarkdownToHTMLForTesting("# Title")
        #expect(html.contains("<h1>Title</h1>"))
    }

    @Test("Converts h2 markdown to HTML")
    func convertsH2() {
        let html = RuleDetailView.convertMarkdownToHTMLForTesting("## Subtitle")
        #expect(html.contains("<h2>Subtitle</h2>"))
    }

    @Test("Converts h3 markdown to HTML")
    func convertsH3() {
        let html = RuleDetailView.convertMarkdownToHTMLForTesting("### Section")
        #expect(html.contains("<h3>Section</h3>"))
    }

    @Test("Converts empty line to br tag")
    func convertsEmptyLineToBr() {
        let html = RuleDetailView.convertMarkdownToHTMLForTesting("")
        #expect(html.contains("<br>"))
    }

    @Test("Converts bold markdown to strong tags")
    func convertsBold() {
        let html = RuleDetailView.convertMarkdownToHTMLForTesting("Use **strong** emphasis.")
        #expect(html.contains("<strong>strong</strong>"))
    }

    @Test("Converts italic markdown to em tags")
    func convertsItalic() {
        let html = RuleDetailView.convertMarkdownToHTMLForTesting("Use *italic* text.")
        #expect(html.contains("<em>italic</em>"))
    }

    @Test("Converts inline code to code tags with monospace style")
    func convertsInlineCode() {
        let html = RuleDetailView.convertMarkdownToHTMLForTesting("Use `let` keyword.")
        #expect(html.contains("<code"))
        #expect(html.contains(">let</code>"))
        #expect(html.contains("SF Mono"))
    }

    @Test("Converts code blocks with language annotation")
    func convertsCodeBlock() {
        let markdown = """
        ```swift
        let value = 42
        ```
        """
        let html = RuleDetailView.convertMarkdownToHTMLForTesting(markdown)
        #expect(html.contains("<pre"))
        #expect(html.contains("language-swift"))
        #expect(html.contains("</code></pre>"))
    }

    @Test("Converts code blocks without language annotation")
    func convertsCodeBlockNoLanguage() {
        let markdown = """
        ```
        plain code
        ```
        """
        let html = RuleDetailView.convertMarkdownToHTMLForTesting(markdown)
        #expect(html.contains("<pre"))
        #expect(html.contains("<code"))
        #expect(!html.contains("language-"))
    }

    @Test("Escapes HTML entities inside code blocks")
    func escapesHTMLInCodeBlocks() {
        let markdown = """
        ```
        let array: Array<Int> = []
        ```
        """
        let html = RuleDetailView.convertMarkdownToHTMLForTesting(markdown)
        // The < and > are escaped to &lt; and &gt; in the code block
        // Raw angle brackets should not appear inside the code content
        #expect(!html.contains("Array<Int>"))
        #expect(html.contains("&lt;"))
        #expect(html.contains("&gt;"))
    }

    @Test("Preserves existing HTML tags in content")
    func preservesExistingHTML() {
        let html = RuleDetailView.convertMarkdownToHTMLForTesting("<div>content</div>")
        #expect(html.contains("<div>content</div>"))
    }

    @Test("Closes unclosed code block at end of content")
    func closesUnclosedCodeBlock() {
        let markdown = """
        ```swift
        let value = 42
        """
        let html = RuleDetailView.convertMarkdownToHTMLForTesting(markdown)
        #expect(html.contains("</code></pre>"))
    }

    // MARK: - wrapHTMLInDocument Tests

    @Test("Dark mode wrapping uses white text color")
    func darkModeWrapping() {
        let wrapped = RuleDetailView.wrapHTMLInDocumentForTesting(
            body: "<p>Hello</p>",
            colorScheme: .dark
        )
        #expect(wrapped.contains("#FFFFFF"))
        #expect(wrapped.contains("<p>Hello</p>"))
    }

    @Test("Light mode wrapping uses black text color")
    func lightModeWrapping() {
        let wrapped = RuleDetailView.wrapHTMLInDocumentForTesting(
            body: "<p>Hello</p>",
            colorScheme: .light
        )
        #expect(wrapped.contains("#000000"))
        #expect(wrapped.contains("<p>Hello</p>"))
    }

    @Test("Wrapping includes style block")
    func wrappingIncludesStyles() {
        let wrapped = RuleDetailView.wrapHTMLInDocumentForTesting(
            body: "",
            colorScheme: .light
        )
        #expect(wrapped.contains("<style>"))
        #expect(wrapped.contains("font-family"))
        #expect(wrapped.contains("pre"))
        #expect(wrapped.contains("code"))
    }

    @Test("Wrapping uses div-based fragment, not full document")
    func wrappingUsesDivFragment() {
        let wrapped = RuleDetailView.wrapHTMLInDocumentForTesting(
            body: "<p>Test</p>",
            colorScheme: .light
        )
        #expect(wrapped.hasPrefix("<div"))
        // Should NOT be a full HTML document
        #expect(!wrapped.contains("<!DOCTYPE"))
        #expect(!wrapped.contains("<html"))
    }
}
