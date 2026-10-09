//
//  SwiftCodeHighlighterTests.swift
//  SwiftLintRuleStudioTests
//
//  The highlighter must colour code without changing it. Its HTML predecessor
//  re-scanned its own markup and leaked text such as `"color: #FC6A5D">` into
//  the displayed examples.
//

@testable import SwiftLintRuleStudio
import SwiftUI
import Testing

@MainActor
struct SwiftCodeHighlighterTests {
    /// The colour applied to the first occurrence of `token` in the highlighted code.
    private func color(of token: String, in code: String) -> Color? {
        let highlighted = SwiftCodeHighlighter.highlight(code)
        guard let range = highlighted.range(of: token) else { return nil }
        return highlighted[range].runs.first?.swiftUI.foregroundColor
    }

    @Test("Highlighting never changes the text, including SwiftLint's ↓ markers")
    func testTextUnchanged() {
        let samples = [
            #"Text("Connected")"#,
            #"Label { Text("Connected") } icon: { Image(systemName: "checkmark.circle.fill") }"#,
            #"Label(content: { Text("Download") }, icon: { Image("custom-download-icon") })"#,
            #"↓Image("my-image").resizable(true).frame(width: 48, height: 48)"#,
            "// a comment with \"quotes\" and let\nlet x = 1 /* block */",
            #"let escaped = "she said \"hi\"""#
        ]
        for code in samples {
            #expect(String(SwiftCodeHighlighter.highlight(code).characters) == code)
        }
    }

    @Test("Keywords, types, strings, numbers and attributes get their colours")
    func testTokenColours() {
        let code = #"@MainActor struct Sample: View { let size = 48; let name = "x" }"#
        #expect(color(of: "@MainActor", in: code) == SwiftCodeHighlighter.Palette.attribute)
        #expect(color(of: "struct", in: code) == SwiftCodeHighlighter.Palette.keyword)
        #expect(color(of: "View", in: code) == SwiftCodeHighlighter.Palette.type)
        #expect(color(of: "48", in: code) == SwiftCodeHighlighter.Palette.number)
        #expect(color(of: #""x""#, in: code) == SwiftCodeHighlighter.Palette.string)
    }

    @Test("Unknown identifiers keep the default colour")
    func testPlainIdentifier() {
        #expect(color(of: "myValue", in: "let myValue = 1") == nil)
    }

    @Test("Words inside a string or comment take that string's or comment's colour")
    func testStringsAndCommentsSwallowTheirContents() {
        let stringCode = #"let label = "let View in""#
        #expect(color(of: "View", in: stringCode) == SwiftCodeHighlighter.Palette.string)

        let commentCode = "// struct View 42"
        #expect(color(of: "struct", in: commentCode) == SwiftCodeHighlighter.Palette.comment)
        #expect(color(of: "42", in: commentCode) == SwiftCodeHighlighter.Palette.comment)
    }

    @Test("Identifiers that only contain a keyword aren't coloured as keywords")
    func testKeywordWithinIdentifier() {
        #expect(color(of: "letter", in: "let letter = 1") == nil)
    }
}
