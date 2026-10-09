//
//  RuleDocSegment.swift
//  SwiftLintRuleStudio
//

import Foundation

/// A piece of a rule's Markdown documentation.
///
/// Fenced code blocks are split out so they can be drawn as their own full-width
/// blocks. Prose still goes through the HTML-to-attributed-string path, but a single
/// `Text` can only shade behind individual runs of text, so code rendered that way got
/// a ragged background that followed each line's length.
enum RuleDocSegment: Equatable {
    case prose(String)
    case code(String)

    /// A segment ready to draw: prose as attributed text built from HTML, code as
    /// attributed text from `SwiftCodeHighlighter`.
    struct Rendered: Identifiable {
        let id: Int
        /// Drawn as a `RuleDocCodeBlock` when true, as plain attributed text otherwise.
        let isCode: Bool
        let text: AttributedString
    }

    /// Splits `markdown` at ``` fences. A fence's info string (such as `swift`) is
    /// dropped, an unclosed fence runs to the end, and blank prose or empty code
    /// between fences is skipped.
    static func split(_ markdown: String) -> [Self] {
        var segments: [Self] = []
        var prose: [String] = []
        var code: [String] = []
        var inCode = false

        func flushProse() {
            let text = prose.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.prose(text))
            }
            prose.removeAll()
        }

        func flushCode() {
            let text = code.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.code(text))
            }
            code.removeAll()
        }

        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if inCode {
                    flushCode()
                } else {
                    flushProse()
                }
                inCode.toggle()
            } else if inCode {
                code.append(line)
            } else {
                prose.append(line)
            }
        }

        if inCode {
            flushCode()
        } else {
            flushProse()
        }
        return segments
    }
}
