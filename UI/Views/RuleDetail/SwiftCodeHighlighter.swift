//
//  SwiftCodeHighlighter.swift
//  SwiftLintRuleStudio
//

import AppKit
import SwiftUI

/// Colours Swift source for display in a single pass over the code.
///
/// Each character belongs to at most one token and is coloured at most once. The HTML
/// highlighter this replaces ran a chain of regex replacements over its own output, so a
/// later pass for quoted strings matched the quotes inside an earlier pass's
/// `<span style="color: …">` and leaked fragments like `"color: #FC6A5D">` into the text.
enum SwiftCodeHighlighter {
    /// Token colours, matching Xcode's default light and dark themes. Each adapts to the
    /// current appearance, so highlighted code doesn't need rebuilding when it changes.
    enum Palette {
        static let keyword = adaptive(light: 0xAD3DA4, dark: 0xFF7AB2)
        static let type = adaptive(light: 0x0B4F79, dark: 0x6BDFFF)
        static let string = adaptive(light: 0xD12F1B, dark: 0xFC6A5D)
        static let number = adaptive(light: 0x1C00CF, dark: 0xD0BF69)
        static let comment = adaptive(light: 0x707F8C, dark: 0x7F8C98)
        static let attribute = adaptive(light: 0x6C36A9, dark: 0xCC85D6)

        private static func adaptive(light: UInt32, dark: UInt32) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return rgb(isDark ? dark : light)
            })
        }

        private static func rgb(_ hex: UInt32) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }

    static func highlight(_ code: String) -> AttributedString {
        var result = AttributedString(code)
        let fullRange = NSRange(code.startIndex..., in: code)
        for match in tokenPattern.matches(in: code, range: fullRange) {
            guard let color = color(for: match, in: code),
                  let stringRange = Range(match.range, in: code),
                  let range = Range(stringRange, in: result) else { continue }
            result[range].swiftUI.foregroundColor = color
        }
        return result
    }

    // Alternatives are tried left to right at each position, and matching resumes after
    // the end of each match, so comments and strings swallow anything inside them.
    private static let tokenPattern: NSRegularExpression = {
        let pattern = [
            #"(//[^\n]*|/\*[\s\S]*?\*/)"#,      // 1: comment
            #"("(?:\\.|[^"\\\n])*")"#,           // 2: string literal
            #"(@[A-Za-z_][A-Za-z0-9_]*)"#,        // 3: attribute
            #"\b(\d[\d_]*(?:\.\d[\d_]*)?)\b"#,    // 4: number
            #"\b([A-Za-z_][A-Za-z0-9_]*)\b"#      // 5: identifier
        ].joined(separator: "|")
        // The pattern is a compile-time constant, so failing to build it is a programmer error.
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static func color(for match: NSTextCheckingResult, in code: String) -> Color? {
        if match.range(at: 1).location != NSNotFound { return Palette.comment }
        if match.range(at: 2).location != NSNotFound { return Palette.string }
        if match.range(at: 3).location != NSNotFound { return Palette.attribute }
        if match.range(at: 4).location != NSNotFound { return Palette.number }
        guard let identifierRange = Range(match.range(at: 5), in: code) else { return nil }
        let identifier = String(code[identifierRange])
        if keywords.contains(identifier) { return Palette.keyword }
        if types.contains(identifier) { return Palette.type }
        return nil
    }

    private static let keywords: Set<String> = [
        "import", "class", "struct", "enum", "protocol",
        "extension", "func", "var", "let", "static",
        "private", "public", "internal", "fileprivate",
        "open", "mutating", "nonmutating", "override",
        "final", "lazy", "weak", "unowned", "typealias",
        "associatedtype", "init", "deinit", "subscript",
        "if", "else", "guard", "switch", "case", "default",
        "for", "while", "repeat", "do", "try", "catch",
        "throw", "throws", "rethrows", "async", "await",
        "return", "break", "continue", "fallthrough",
        "where", "in", "as", "is", "self", "Self", "super",
        "nil", "true", "false", "some", "any", "inout",
        "convenience", "required", "optional", "indirect",
        "get", "set", "willSet", "didSet", "defer",
        "precondition", "assert", "nonisolated",
        "consuming", "borrowing", "sending"
    ]

    private static let types: Set<String> = [
        "String", "Int", "Double", "Float", "Bool",
        "Character", "Void", "Array", "Dictionary", "Set",
        "Optional", "Result", "Error", "Any", "AnyObject",
        "AnyHashable", "Never", "URL", "Data", "Date",
        "UUID", "Codable", "Hashable", "Equatable",
        "Comparable", "Identifiable", "Sendable",
        "ObservableObject", "Published", "StateObject",
        "ObservedObject", "EnvironmentObject", "State",
        "Binding", "Environment", "View", "Scene", "App",
        "Text", "Image", "Button", "List",
        "NavigationView", "NavigationStack",
        "VStack", "HStack", "ZStack",
        "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "CGFloat", "CGPoint", "CGSize", "CGRect", "NSObject"
    ]
}
