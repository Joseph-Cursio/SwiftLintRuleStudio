//
//  MirrorExclusions.swift
//  SwiftLintRuleStudio
//
//  Whether SwiftLint's `excluded` patterns keep it out of a path.
//

import Foundation

/// The root config's `excluded` patterns, matched as SwiftLint matches them: Python `fnmatch`
/// with `**` for any run of folders (its `FilenameMatcher`), case-sensitive, against the whole
/// absolute path, and a pattern naming a folder taking everything in it.
///
/// The mirror itself never needs this — SwiftLint applies the exclusions in the mirror — except
/// to tell whether SwiftLint walks into a link that loops, which it follows until it crashes.
nonisolated struct MirrorExclusions: Sendable {
    private let expressions: [NSRegularExpression]

    /// - Parameter patterns: Absolute, as SwiftLint makes each entry: its config's folder joined
    ///   with it.
    init(patterns: [String]) {
        expressions = patterns.flatMap(Self.matcherPatterns).compactMap { pattern in
            try? NSRegularExpression(pattern: "^(?s:" + Self.translate(pattern) + ")$")
        }
    }

    /// Whether SwiftLint excludes the file or folder at the absolute `path`.
    func excludes(_ path: String) -> Bool {
        let range = NSRange(path.startIndex..., in: path)
        return expressions.contains { $0.firstMatch(in: path, range: range) != nil }
    }

    /// SwiftLint's `Glob.createFilenameMatchers`: a pattern also covers what is inside a folder
    /// it names.
    private static func matcherPatterns(_ pattern: String) -> [String] {
        if pattern.hasSuffix(".swift") || pattern.hasSuffix("/**") { return [pattern] }
        if pattern.hasSuffix("/") { return [pattern + "**"] }
        return [pattern, pattern + "/**"]
    }

    /// `fnmatch.translate` with globstar: `*` matches across `/`, as in Python, and `**/`
    /// matches no folder or any number of them.
    static func translate(_ pattern: String) -> String {
        let characters = Array(pattern)
        var result = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            index += 1
            switch character {
            case "*":
                if index < characters.count, characters[index] == "*" {
                    index += 1
                    if index < characters.count, characters[index] == "/" {
                        index += 1
                        result += "(?:.*/)?"
                    } else {
                        result += ".*"
                    }
                } else {
                    result += ".*"
                }
            case "?":
                result += "."
            case "[":
                guard let (set, next) = characterSet(in: characters, from: index) else {
                    result += "\\["
                    continue
                }
                result += set
                index = next
            default:
                result += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        return result
    }

    /// The bracket expression starting after a `[` at `start`, and where it ends, or nil when it
    /// never closes (then the `[` is literal, as in `fnmatch`).
    private static func characterSet(in characters: [Character], from start: Int) -> (String, Int)? {
        var end = start
        if end < characters.count, characters[end] == "!" { end += 1 }
        if end < characters.count, characters[end] == "]" { end += 1 }
        while end < characters.count, characters[end] != "]" { end += 1 }
        guard end < characters.count else { return nil }
        var body = String(characters[start..<end]).replacingOccurrences(of: "\\", with: "\\\\")
        if body.hasPrefix("!") { body = "^" + body.dropFirst() } else if body.hasPrefix("^") { body = "\\" + body }
        return ("[" + body + "]", end + 1)
    }
}
