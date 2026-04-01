//
//  RuleDetailViewMarkdownTests.swift
//  SwiftLintRuleStudioTests
//
//  Markdown processing tests for RuleDetailView
//

import SwiftUI
import Testing
@testable import SwiftLintRuleStudioCore
@testable import SwiftLintRuleStudio

@MainActor
struct RuleDetailViewMarkdownTests {
    @Test("RuleDetailView strips rationale section from display content")
    func testRuleDetailViewMarkdownProcessing() async throws {
        let markdown = """
        # Test Rule

        ## Why This Matters

        Use **bold** and `code`.

        ## Examples

        Some examples here.
        """
        let processed = await MainActor.run {
            RuleDetailView.processContentForDisplayForTesting(markdown)
        }
        // Rationale is shown separately in "Why This Matters" view
        #expect(!processed.contains("Why This Matters"))
        #expect(!processed.contains("Use **bold**"))
        // Non-rationale sections should remain
        #expect(processed.contains("Examples"))
    }

    @Test("RuleDetailView converts markdown to HTML")
    func testRuleDetailViewMarkdownToHTML() async throws {
        let markdown = "This is **bold** and `code`."
        let html = await MainActor.run {
            RuleDetailView.convertMarkdownToHTMLForTesting(markdown)
        }
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains(">code</code>"))
    }

    @Test("RuleDetailView wraps HTML with dark mode styles")
    func testRuleDetailViewHTMLDarkMode() async throws {
        let html = "<p>Test</p>"
        let wrapped = await MainActor.run {
            RuleDetailView.wrapHTMLInDocumentForTesting(body: html, colorScheme: .dark)
        }
        #expect(wrapped.contains("#FFFFFF"))
        #expect(wrapped.contains(html))
    }

    @Test("RuleDetailView hides short description when markdown contains it")
    func testRuleDetailViewHidesShortDescription() async throws {
        let markdown = """
        # Test Rule

        Test description
        """
        let processed = await MainActor.run {
            RuleDetailView.processContentForDisplayForTesting(markdown)
        }
        #expect(processed.contains("# Test Rule") == false)
    }

    @Test("RuleDetailView markdown helpers process content")
    func testMarkdownHelpers() async throws {
        let markdown = """
        # Title

        Regular text
        """
        let result = await MainActor.run {
            RuleDetailView.processContentForDisplayForTesting(markdown)
        }
        #expect(result.contains("Title") == false)
        #expect(result.contains("Regular text"))
    }
}
