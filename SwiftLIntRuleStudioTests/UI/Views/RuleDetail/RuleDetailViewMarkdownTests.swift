//
//  RuleDetailViewMarkdownTests.swift
//  SwiftLIntRuleStudioTests
//
//  Markdown processing tests for RuleDetailView
//

import SwiftUI
import Testing
@testable import SwiftLIntRuleStudio

@Suite(.serialized)
struct RuleDetailViewMarkdownTests {
    @Test("RuleDetailView processes markdown content for display")
    func testRuleDetailViewMarkdownProcessing() async throws {
        let markdown = """
        # Test Rule

        ## Why This Matters

        Use **bold** and `code`.
        """
        let processed = await MainActor.run {
            RuleDetailView.processContentForDisplayForTesting(markdown)
        }
        #expect(processed.contains("Why This Matters"))
    }

    @Test("RuleDetailView converts markdown to HTML")
    func testRuleDetailViewMarkdownToHTML() async throws {
        let markdown = "This is **bold** and `code`."
        let html = await MainActor.run {
            RuleDetailView.convertMarkdownToHTMLForTesting(markdown)
        }
        #expect(html.contains("<strong>bold</strong>") == true)
        #expect(html.contains("<code>code</code>") == true)
    }

    @Test("RuleDetailView wraps HTML with dark mode styles")
    func testRuleDetailViewHTMLDarkMode() async throws {
        let html = "<p>Test</p>"
        let wrapped = await MainActor.run {
            RuleDetailView.wrapHTMLInDocumentForTesting(body: html, colorScheme: .dark)
        }
        #expect(wrapped.contains("#FFFFFF") == true)
        #expect(wrapped.contains(html) == true)
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
        #expect(result.contains("Regular text") == true)
    }
}
