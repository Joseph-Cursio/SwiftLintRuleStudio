//
//  SwiftCodeHighlighterTests.swift
//  SwiftLintRuleStudioTests
//
//  The highlighter must colour code without changing it. Its HTML predecessor
//  re-scanned its own markup and leaked text such as `"color: #FC6A5D">` into
//  the displayed examples.
//

import AppKit
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

    // MARK: - Palette

    private static let palette: [Color] = [
        SwiftCodeHighlighter.Palette.keyword, SwiftCodeHighlighter.Palette.type,
        SwiftCodeHighlighter.Palette.string, SwiftCodeHighlighter.Palette.number,
        SwiftCodeHighlighter.Palette.comment, SwiftCodeHighlighter.Palette.attribute
    ]

    /// The 0xRRGGBB value `color` resolves to under the named appearance.
    private func hex(of color: Color, in appearanceName: NSAppearance.Name) -> UInt32? {
        var result: UInt32?
        NSAppearance(named: appearanceName)?.performAsCurrentDrawingAppearance {
            guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            let red = UInt32((srgb.redComponent * 255).rounded())
            let green = UInt32((srgb.greenComponent * 255).rounded())
            let blue = UInt32((srgb.blueComponent * 255).rounded())
            result = red << 16 | green << 8 | blue
        }
        return result
    }

    @Test("Palette colours follow Xcode's light and dark themes")
    func testPaletteAdaptsToAppearance() {
        #expect(hex(of: SwiftCodeHighlighter.Palette.string, in: .aqua) == 0xD12F1B)
        #expect(hex(of: SwiftCodeHighlighter.Palette.string, in: .darkAqua) == 0xFC6A5D)
        #expect(hex(of: SwiftCodeHighlighter.Palette.keyword, in: .aqua) == 0xAD3DA4)
        #expect(hex(of: SwiftCodeHighlighter.Palette.keyword, in: .darkAqua) == 0xFF7AB2)
    }

    // AppKit may resolve a dynamic colour off the main thread. If the provider were
    // main-actor isolated (this target's default), resolving it here would trap and take
    // the whole test process down, so a regression shows up as a crash in this test.
    @Test("Palette colours resolve on a background thread")
    func testPaletteResolvesOffMainThread() async {
        nonisolated(unsafe) let colors = Self.palette.map { NSColor($0) }
        let resolved = await Task.detached {
            colors.map { $0.usingColorSpace(.sRGB) != nil }
        }.value
        #expect(resolved.count == 6)
        #expect(!resolved.contains(false))
    }
}
