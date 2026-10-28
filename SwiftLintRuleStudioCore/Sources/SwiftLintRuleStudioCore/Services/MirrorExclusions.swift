//
//  MirrorExclusions.swift
//  SwiftLintRuleStudio
//
//  Whether SwiftLint's `excluded` patterns keep it out of a path.
//

import Foundation

/// The root config's `excluded` patterns, matched as SwiftLint matches them: Python `fnmatch`
/// with `**` for any run of folders (its `FilenameMatcher`), against the whole absolute path,
/// and a pattern naming a folder taking everything in it.
///
/// The mirror itself never needs this — SwiftLint applies the exclusions in the mirror — except
/// to tell whether SwiftLint walks into a link that loops, which it follows until it crashes.
/// So it only counts an exclusion SwiftLint surely applies: SwiftLint ignores case, and a path
/// matching both ignoring and minding case is one it excludes, while minding case alone could
/// take one it doesn't — `[!a]` takes `A`, and a `**/` before more of the pattern settles on a
/// different folder.
nonisolated struct MirrorExclusions: Sendable {
    /// Each pattern twice: as SwiftLint matches it, ignoring case, and minding case.
    private let expressions: [(caseless: NSRegularExpression, cased: NSRegularExpression)]

    /// - Parameter patterns: Absolute, as SwiftLint makes each entry: its config's folder joined
    ///   with it.
    init(patterns: [String]) {
        expressions = patterns.flatMap(Self.matcherPatterns).compactMap { pattern in
            let expression = "^(?s:" + Self.translate(pattern) + ")$"
            guard let caseless = try? NSRegularExpression(pattern: expression, options: .caseInsensitive),
                  let cased = try? NSRegularExpression(pattern: expression) else { return nil }
            return (caseless, cased)
        }
    }

    /// Whether SwiftLint surely excludes the file or folder at the absolute `path`.
    func excludes(_ path: String) -> Bool {
        let range = NSRange(path.startIndex..., in: path)
        return expressions.contains { pair in
            [pair.caseless, pair.cased].allSatisfy { $0.firstMatch(in: path, range: range) != nil }
        }
    }

    /// SwiftLint's `Glob.createFilenameMatchers`: a pattern also covers what is inside a folder
    /// it names.
    private static func matcherPatterns(_ pattern: String) -> [String] {
        if pattern.hasSuffix(".swift") || pattern.hasSuffix("/**") { return [pattern] }
        if pattern.hasSuffix("/") { return [pattern + "**"] }
        return [pattern, pattern + "/**"]
    }

    /// A piece of a pattern: a run of `*`, or text that matches as it stands.
    private enum Part: Equatable {
        case stars(Int)
        case fixed(String)
    }

    /// `fnmatch.translate` with globstar, as SwiftLint's `FilenameMatcher` has it: `*` matches
    /// across `/`, as in Python, and `**/` matches no folder or any number of them.
    static func translate(_ pattern: String) -> String {
        let characters = Array(pattern)
        var parts: [Part] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            index += 1
            switch character {
            case "*":
                if case .stars(let count) = parts.last {
                    parts[parts.count - 1] = .stars(count + 1)
                } else {
                    parts.append(.stars(1))
                }
            case "?":
                parts.append(.fixed("."))
            case "[":
                guard let (set, next) = characterSet(in: characters, from: index) else {
                    parts.append(.fixed("\\["))
                    continue
                }
                parts.append(.fixed(set))
                index = next
            case "/" where parts.last == .stars(2):
                parts[parts.count - 1] = .fixed("(?:.*/)?")
            default:
                parts.append(.fixed(NSRegularExpression.escapedPattern(for: String(character))))
            }
        }
        return assembled(parts)
    }

    /// The text before the first star as it stands; each star after it with the text up to the
    /// next one, matching as little as it can and never giving it back, `(?>.*?text)`; the last
    /// star as much as it can. So a star doesn't backtrack into what the text after it matched,
    /// and SwiftLint doesn't match some paths a plain `.*` would.
    private static func assembled(_ parts: [Part]) -> String {
        var runs = [""]
        for part in parts {
            switch part {
            case .stars:
                runs.append("")
            case .fixed(let text):
                runs[runs.count - 1] += text
            }
        }
        let leading = runs.removeFirst()
        let starred = runs.enumerated().map { index, run in
            index == runs.count - 1 ? ".*" + run : "(?>.*?" + run + ")"
        }
        return leading + starred.joined()
    }

    /// The bracket expression starting after a `[` at `start`, and where it ends, or nil when it
    /// never closes (then the `[` is literal, as in `fnmatch`).
    private static func characterSet(in characters: [Character], from start: Int) -> (String, Int)? {
        var end = start
        if end < characters.count, characters[end] == "!" { end += 1 }
        if end < characters.count, characters[end] == "]" { end += 1 }
        while end < characters.count, characters[end] != "]" { end += 1 }
        guard end < characters.count else { return nil }
        var body = setBody(characters, from: start, to: end)
        // `&&`, `~~` and `||` are set operations in ICU. SwiftLint's matcher means to escape each
        // `&`, `~` and `|` but writes `\1` in its place, which matches none of them; so does this,
        // never counting on a match SwiftLint might not make.
        body = body.replacingOccurrences(of: "[&~|]", with: "\\\\1", options: .regularExpression)
        if body.isEmpty { return ("(?!)", end + 1) }
        if body == "!" { return (".", end + 1) }
        if body.hasPrefix("!") {
            body = "^" + body.dropFirst()
        } else if body.hasPrefix("^") || body.hasPrefix("[") {
            body = "\\" + body
        }
        return ("[" + body + "]", end + 1)
    }

    /// The characters of a set from `start` to `end`, `\` escaped, with a `-` kept as a range only
    /// between two characters and a range running backwards dropped, as `fnmatch` does.
    private static func setBody(_ characters: [Character], from start: Int, to end: Int) -> String {
        guard characters[start..<end].contains("-") else {
            return String(characters[start..<end]).replacingOccurrences(of: "\\", with: "\\\\")
        }
        var chunks: [String] = []
        var chunkStart = start
        var search = characters[start] == "!" ? start + 2 : start + 1
        while search < end, let hyphen = characters[search..<end].firstIndex(of: "-") {
            chunks.append(String(characters[chunkStart..<hyphen]))
            chunkStart = hyphen + 1
            search = hyphen + 3
        }
        let last = String(characters[chunkStart..<end])
        if !last.isEmpty {
            chunks.append(last)
        } else if let previous = chunks.popLast() {
            chunks.append(previous + "-")
        }
        var index = chunks.count - 1
        while index > 0 {
            if let previous = chunks[index - 1].last, let first = chunks[index].first, previous > first {
                chunks[index - 1] = String(chunks[index - 1].dropLast()) + chunks[index].dropFirst()
                chunks.remove(at: index)
            }
            index -= 1
        }
        let escaped = chunks.map {
            $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "-", with: "\\-")
        }
        return escaped.joined(separator: "-")
    }
}
