//
//  MirrorLinkReach.swift
//  SwiftLintRuleStudio
//
//  Which symlinked folders SwiftLint can reach, as far as the mirror needs to know.
//

import Foundation

/// Which symlinked folders SwiftLint can reach in the real workspace, worked out from the root
/// config so the mirror doesn't walk — or copy — folders SwiftLint never lints.
///
/// It only has to over-approximate: the mirror keeps links as links, and SwiftLint linting the
/// mirror makes the exact decision. Leaving out a folder SwiftLint does reach would make it
/// measure 0, so every doubt goes toward reaching.
nonisolated enum MirrorLinkReach: Sendable, Equatable {
    /// A config excludes something. SwiftLint then resolves every link it meets and walks it.
    case everyLink
    /// No config excludes anything. SwiftLint lists files with `FileManager.subpaths(atPath:)`,
    /// which goes into no link, so it reaches a link only on the way to an `included` entry —
    /// each entry's standardized path components relative to the workspace here, `..` first
    /// for one beside it — and with no `included`, none at all.
    case towardIncluded([[String]])

    /// Whether SwiftLint may follow a link to a folder at `path` (relative to the workspace).
    func follows(linkAt path: String) -> Bool {
        switch self {
        case .everyLink: true
        case .towardIncluded(let entries): entries.contains { Self.isOnTheWay(path, to: $0) }
        }
    }

    /// Whether a folder at `path` may hold a link SwiftLint follows.
    func mayHoldReachableLinks(_ path: String) -> Bool {
        follows(linkAt: path)
    }

    /// Whether `path` is an entry, or lies on the way to one: compared component by
    /// component, ignoring case — SwiftLint lists files on the case-insensitive volumes macOS
    /// defaults to — with globs matching as glob(3) would, and `**` or a brace pattern taken to
    /// reach anything below it.
    private static func isOnTheWay(_ path: String, to entry: [String]) -> Bool {
        let expandsBraces = expandsBraces(entry)
        for (index, component) in path.split(separator: "/").map(String.init).enumerated() {
            // Beneath a whole entry: `subpaths` lists it but goes into no link inside it.
            guard index < entry.count else { return false }
            let pattern = entry[index]
            if reachesAnything(pattern, expandsBraces: expandsBraces) { return true }
            guard matches(pattern, component) else { return false }
        }
        return true
    }

    /// Whether `path` (relative to the workspace) is one of `entries` or lies beneath one —
    /// where SwiftLint walks — compared as the way to an entry is.
    static func isWithin(_ path: String, anyOf entries: [[String]]) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        return entries.contains { entry in
            let expandsBraces = expandsBraces(entry)
            for (index, pattern) in entry.enumerated() {
                if reachesAnything(pattern, expandsBraces: expandsBraces) { return true }
                guard index < components.count, matches(pattern, components[index]) else { return false }
            }
            return true
        }
    }

    /// How deep below the workspace the walk that reaches `path` starts: the most components of
    /// any of `entries` it lies within, as ``isWithin(_:anyOf:)`` has it. Nil when it lies within
    /// none, or within one with `**` or braces, which may start a walk at any depth.
    static func walkStartDepth(of path: String, in entries: [[String]]) -> Int? {
        var depth: Int?
        for entry in entries where isWithin(path, anyOf: [entry]) {
            if entry.contains(where: { reachesAnything($0, expandsBraces: expandsBraces(entry)) }) { return nil }
            depth = max(depth ?? 0, entry.count)
        }
        return depth
    }

    /// `**` and brace patterns are taken to reach anything below them.
    private static func reachesAnything(_ pattern: String, expandsBraces: Bool) -> Bool {
        pattern.contains("**") || (expandsBraces && pattern.contains("{"))
    }

    /// SwiftLint expands an entry as a glob — braces included — only when it holds `*`, `?`
    /// or `[`; otherwise `{A,B}` is a folder's name.
    private static func expandsBraces(_ entry: [String]) -> Bool {
        entry.contains { $0.rangeOfCharacter(from: CharacterSet(charactersIn: "*?[]")) != nil }
    }

    private static func matches(_ pattern: String, _ component: String) -> Bool {
        pattern.caseInsensitiveCompare(component) == .orderedSame
            || (hasGlob(pattern) && fnmatch(pattern, component, FNM_CASEFOLD) == 0)
    }

    static func hasGlob(_ pattern: String) -> Bool {
        pattern.rangeOfCharacter(from: CharacterSet(charactersIn: "*?[]{")) != nil
    }
}
