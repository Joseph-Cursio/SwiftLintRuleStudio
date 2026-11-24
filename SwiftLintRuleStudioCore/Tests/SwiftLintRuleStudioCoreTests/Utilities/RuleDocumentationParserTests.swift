//
//  RuleDocumentationParserTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for RuleDocumentationParser static parsing logic
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct RuleDocumentationParserTests {

    // MARK: - Title Parsing

    @Test("Parses rule name from H1 heading")
    func testParsesTitle() {
        let markdown = "# Force Cast\n\nSome description."
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.name == "Force Cast")
    }

    @Test("Returns empty name when markdown has no H1 heading")
    func testEmptyNameWithoutTitle() {
        let markdown = "Some description without a title."
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.name.isEmpty)
    }

    @Test("Returns empty fields for empty markdown")
    func testEmptyMarkdown() {
        let result = RuleDocumentationParser.parse(markdown: "")
        #expect(result.name.isEmpty)
        #expect(result.description.isEmpty)
        #expect(result.supportsAutocorrection == false)
        #expect(result.triggeringExamples.isEmpty)
        #expect(result.nonTriggeringExamples.isEmpty)
    }

    // MARK: - Description Extraction

    @Test("Extracts description paragraph after title")
    func testExtractsDescription() {
        let markdown = """
        # Force Cast

        Force casts should be avoided because they can crash at runtime.
        """
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.description == "Force casts should be avoided because they can crash at runtime.")
    }

    @Test("Stops description extraction at metadata bullet line")
    func testDescriptionStopsAtMetadata() {
        let markdown = """
        # Rule Name

        This is the description.
        * **Identifier:** `rule_name`
        """
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.description == "This is the description.")
    }

    @Test("Stops description extraction at H2 section heading")
    func testDescriptionStopsAtH2() {
        let markdown = """
        # Rule Name

        This is the description.

        ## Triggering Examples

        Some example text.
        """
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.description == "This is the description.")
    }

    @Test("Stops description extraction at code fence")
    func testDescriptionStopsAtCodeFence() {
        let markdown = """
        # Rule Name

        This is the description.
        ```swift
        let x = 1
        ```
        """
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.description == "This is the description.")
    }

    @Test("Truncates long description at sentence boundary near 250 characters")
    func testTruncatesAtSentenceBoundary() {
        // Construct a description where the first sentence ends before 250 chars
        // and the second sentence pushes over 250 chars total
        let short = "First sentence that ends here."
        let padding = String(repeating: "x", count: 200)
        let long = "Second sentence that is very long and \(padding) pushes total over limit."
        let markdown = "# Rule\n\n\(short) \(long)"

        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.description.count <= 250)
        #expect(result.description.hasSuffix("."))
        #expect(result.description.contains("pushes total over limit") == false)
    }

    @Test("Appends ellipsis when no sentence boundary found near 250 characters")
    func testEllipsisWhenNoSentenceBoundary() {
        let noSentences = String(repeating: "word ", count: 60) // well over 250 chars, no periods
        let markdown = "# Rule\n\n\(noSentences)"
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.description.hasSuffix("..."))
        #expect(result.description.count <= 254) // 250 trimmed chars + "..."
    }

    @Test("Short description under 250 characters is returned unchanged")
    func testShortDescriptionUnchanged() {
        let short = "Brief rule description."
        let markdown = "# Rule\n\n\(short)"
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.description == short)
    }

    // MARK: - Metadata Parsing

    @Test("Detects supportsAutocorrection = true when value is Yes")
    func testSupportsAutocorrectionYes() {
        let markdown = """
        # Rule

        Description.

        * **Supports autocorrection:** Yes
        """
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.supportsAutocorrection)
    }

    @Test("Detects supportsAutocorrection = false when value is No")
    func testSupportsAutocorrectionNo() {
        let markdown = """
        # Rule

        Description.

        * **Supports autocorrection:** No
        """
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.supportsAutocorrection == false)
    }

    @Test("Extracts minimum Swift compiler version from metadata")
    func testExtractsMinimumSwiftVersion() {
        let markdown = """
        # Rule

        Description.

        * **Minimum Swift compiler version:** `5.7`
        """
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.minimumSwiftVersion == "5.7")
    }

    @Test("Returns nil minimumSwiftVersion when not present in markdown")
    func testNilMinimumSwiftVersionWhenAbsent() {
        let markdown = "# Rule\n\nDescription."
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.minimumSwiftVersion == nil)
    }

    @Test("Preserves full original markdown in result")
    func testPreservesFullMarkdown() {
        let markdown = "# Rule\n\nDescription.\n\n## Triggering Examples\n"
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.fullMarkdown == markdown)
    }
}
