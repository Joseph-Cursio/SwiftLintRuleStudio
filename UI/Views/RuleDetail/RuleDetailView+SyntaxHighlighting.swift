import SwiftUI

extension RuleDetailView {

    struct SyntaxColors {
        let keyword: String
        let type: String
        let string: String
        let number: String
        let comment: String
        let attribute: String

        static let light = SyntaxColors(
            keyword: "#AD3DA4",
            type: "#0B4F79",
            string: "#D12F1B",
            number: "#1C00CF",
            comment: "#707F8C",
            attribute: "#6C36A9"
        )

        static let dark = SyntaxColors(
            keyword: "#FF7AB2",
            type: "#6BDFFF",
            string: "#FC6A5D",
            number: "#D0BF69",
            comment: "#7F8C98",
            attribute: "#CC85D6"
        )
    }

    func highlightSwiftSyntax(
        in escapedLine: String,
        colorScheme: ColorScheme?
    ) -> String {
        let colors = (colorScheme == .dark)
            ? SyntaxColors.dark : SyntaxColors.light
        var result = escapedLine

        // Order matters: comments first (to avoid highlighting inside
        // comments), then strings, then keywords/types/attributes/numbers

        // Single-line comments: // ...
        if let commentRange = result.range(
            of: #"//.*$"#, options: .regularExpression
        ) {
            let comment = String(result[commentRange])
            let wrapped = "<span style=\"color: \(colors.comment); " +
                "font-style: italic;\">\(comment)</span>"
            result = result.replacingCharacters(
                in: commentRange, with: wrapped
            )
            return result
        }

        // String literals (HTML-escaped quotes from &amp; encoding)
        result = result.replacingOccurrences(
            of: #"&quot;([^&]*?)&quot;"#,
            with: "<span style=\"color: \(colors.string)\">" +
                "&quot;$1&quot;</span>",
            options: .regularExpression
        )
        // String literals that use actual quote characters
        result = result.replacingOccurrences(
            of: #""([^"]*?)""#,
            with: "<span style=\"color: \(colors.string)\">" +
                "\"$1\"</span>",
            options: .regularExpression
        )

        // Attributes (@MainActor, @objc, @discardableResult, etc.)
        result = result.replacingOccurrences(
            of: #"(@[A-Za-z_][A-Za-z0-9_]*)"#,
            with: "<span style=\"color: \(colors.attribute)\">$1</span>",
            options: .regularExpression
        )

        result = highlightKeywordsAndTypes(
            in: result, colors: colors
        )

        return result
    }

    private func highlightKeywordsAndTypes(
        in text: String,
        colors: SyntaxColors
    ) -> String {
        var result = highlightKeywords(in: text, colors: colors)
        result = highlightTypes(in: result, colors: colors)

        // Numeric literals (integers and floats)
        result = result.replacingOccurrences(
            of: #"\b(\d[\d_]*\.?\d*)\b"#,
            with: "<span style=\"color: \(colors.number)\">$1</span>",
            options: .regularExpression
        )

        return result
    }

    private func highlightKeywords(
        in text: String,
        colors: SyntaxColors
    ) -> String {
        let keywords = [
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
        let pattern = #"\b("# +
            keywords.joined(separator: "|") + #")\b"#
        return text.replacingOccurrences(
            of: pattern,
            with: "<span style=\"color: \(colors.keyword)\">$1</span>",
            options: .regularExpression
        )
    }

    private func highlightTypes(
        in text: String,
        colors: SyntaxColors
    ) -> String {
        let types = [
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
        let pattern = #"\b("# +
            types.joined(separator: "|") + #")\b"#
        return text.replacingOccurrences(
            of: pattern,
            with: "<span style=\"color: \(colors.type)\">$1</span>",
            options: .regularExpression
        )
    }
}
