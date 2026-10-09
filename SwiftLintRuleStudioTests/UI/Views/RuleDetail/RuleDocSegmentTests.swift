//
//  RuleDocSegmentTests.swift
//  SwiftLintRuleStudioTests
//
//  Splitting rule documentation into prose and fenced code blocks, so code can be
//  drawn as its own full-width block.
//

@testable import SwiftLintRuleStudio
import Testing

@MainActor
struct RuleDocSegmentTests {
    @Test("Markdown with no fences is one prose segment")
    func testNoFences() {
        #expect(RuleDocSegment.split("Just prose.\nMore prose.") == [.prose("Just prose.\nMore prose.")])
    }

    @Test("Prose, code and prose come out in order, with fences and info strings removed")
    func testProseCodeProse() {
        let markdown = """
        ## Triggering Examples
        ```swift
        let a = 1
        let b = 2
        ```
        After the code.
        """
        #expect(RuleDocSegment.split(markdown) == [
            .prose("## Triggering Examples"),
            .code("let a = 1\nlet b = 2"),
            .prose("After the code.")
        ])
    }

    @Test("Consecutive code blocks stay separate, and blank prose between them is skipped")
    func testConsecutiveCodeBlocks() {
        let markdown = """
        ```swift
        first()
        ```

        ```swift
        second()
        ```
        """
        #expect(RuleDocSegment.split(markdown) == [.code("first()"), .code("second()")])
    }

    @Test("An unclosed fence runs to the end")
    func testUnclosedFence() {
        let markdown = """
        Intro
        ```swift
        let value = 42
        """
        #expect(RuleDocSegment.split(markdown) == [.prose("Intro"), .code("let value = 42")])
    }

    @Test("An empty code block is skipped")
    func testEmptyCodeBlock() {
        #expect(RuleDocSegment.split("Intro\n```\n```\nOutro") == [.prose("Intro"), .prose("Outro")])
    }

    @Test("Indentation inside code is kept")
    func testIndentationKept() {
        let markdown = "```swift\nstruct A {\n    let b = 1\n}\n```"
        #expect(RuleDocSegment.split(markdown) == [.code("struct A {\n    let b = 1\n}")])
    }
}
