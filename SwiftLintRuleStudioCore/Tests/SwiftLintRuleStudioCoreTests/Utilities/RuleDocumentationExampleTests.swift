//
//  RuleDocumentationExampleTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for how RuleDocumentationParser extracts triggering and non-triggering examples
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct RuleDocumentationExampleTests {
    // MARK: - Example Extraction

    @Test("Extracts triggering examples from H2 Triggering Examples section")
    func testExtractsTriggeringExamples() throws {
        let markdown = """
        # Force Cast

        Description.

        ## Triggering Examples

        ```swift
        let x = foo as! Bar
        ```

        ```swift
        let y = baz as! Qux
        ```
        """
        let result = RuleDocumentationParser.parse(markdown: markdown)
        try #require(result.triggeringExamples.count == 2)
        #expect(result.triggeringExamples[0].contains("as! Bar"))
        #expect(result.triggeringExamples[1].contains("as! Qux"))
    }

    @Test("Extracts non-triggering examples from H2 Non Triggering Examples section")
    func testExtractsNonTriggeringExamples() throws {
        let markdown = """
        # Force Cast

        Description.

        ## Non Triggering Examples

        ```swift
        if let x = foo as? Bar { }
        ```
        """
        let result = RuleDocumentationParser.parse(markdown: markdown)
        try #require(result.nonTriggeringExamples.count == 1)
        #expect(result.nonTriggeringExamples[0].contains("as? Bar"))
    }

    @Test("Handles Non-Triggering section name spelled with hyphen")
    func testHyphenatedNonTriggeringSectionName() {
        let markdown = """
        # Rule

        Description.

        ## Non-Triggering Examples

        ```swift
        let good = foo
        ```
        """
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.nonTriggeringExamples.count == 1)
    }

    @Test("Extracts both example types from a full documentation block")
    func testExtractsBothExampleTypes() {
        let markdown = """
        # Rule

        Description.

        ## Non Triggering Examples

        ```swift
        let good = foo
        ```

        ## Triggering Examples

        ```swift
        let bad = bar
        ```
        """
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.nonTriggeringExamples.count == 1)
        #expect(result.triggeringExamples.count == 1)
    }

    @Test("Returns empty examples for markdown with no code blocks")
    func testNoExamplesInPlainMarkdown() {
        let markdown = "# Rule\n\nDescription without examples.\n\n## Triggering Examples\n\nSome text."
        let result = RuleDocumentationParser.parse(markdown: markdown)
        #expect(result.triggeringExamples.isEmpty)
        #expect(result.nonTriggeringExamples.isEmpty)
    }

    @Test("Parameterized: correctly categorizes examples by section", arguments: [
        ("triggering", "## Triggering Examples", true),
        ("nontriggering", "## Non Triggering Examples", false),
    ])
    func testExampleCategorization(id _: String, sectionHeader: String, isTriggering: Bool) {
        let markdown = """
        # Rule

        Description.

        \(sectionHeader)

        ```swift
        let example = 1
        ```
        """
        let result = RuleDocumentationParser.parse(markdown: markdown)
        if isTriggering {
            #expect(result.triggeringExamples.count == 1)
            #expect(result.nonTriggeringExamples.isEmpty)
        } else {
            #expect(result.nonTriggeringExamples.count == 1)
            #expect(result.triggeringExamples.isEmpty)
        }
    }
}
