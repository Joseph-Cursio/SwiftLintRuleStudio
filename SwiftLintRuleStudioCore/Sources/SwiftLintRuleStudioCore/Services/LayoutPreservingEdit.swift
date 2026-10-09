//
//  LayoutPreservingEdit.swift
//  SwiftLintRuleStudio
//
//  Writing a configuration as an edit of the file it replaces.
//

import Foundation
import Yams

/// One top-level key and the lines that belong to it.
private struct LayoutSection {
    let key: String
    /// Column-0 comment lines directly above the key line.
    var leading: [String]
    var keyLine: String
    /// The value's lines below the key line.
    var core: [String]
    /// Blank lines and column-0 comments after the value, up to the next section.
    var tail: [String]

    var lines: [String] { leading + [keyLine] + core + tail }
}

/// A file as the lines before its first section, then its sections.
private struct LayoutDocument {
    var prefix: [String]
    var sections: [LayoutSection]

    /// The lines, ending with a newline whether or not the file did, as `serialize(_:)`'s do.
    var text: String {
        (prefix + sections.flatMap(\.lines)).joined(separator: "\n") + "\n"
    }

    /// Nil for anything but a block mapping of unique keys: flow style, several documents, or
    /// CRLF line endings. Anchors and aliases need no check here: a section that uses another's
    /// anchor doesn't parse on its own, so it's regenerated rather than kept.
    init?(_ text: String) {
        guard !text.isEmpty, !text.contains("\r") else { return nil }
        var lines = text.components(separatedBy: "\n")
        if lines.last?.isEmpty == true { lines.removeLast() }
        guard let keyLines = Self.keyLines(in: lines) else { return nil }

        // A section starts at the comments directly above its key line.
        let starts = keyLines.enumerated().map { position, keyLine in
            var start = keyLine.index
            let floor = position == 0 ? 0 : keyLines[position - 1].index + 1
            while start > floor, lines[start - 1].hasPrefix("#") {
                start -= 1
            }
            return start
        }

        prefix = Array(lines[0 ..< starts[0]])
        sections = keyLines.enumerated().map { position, keyLine in
            let end = position + 1 < starts.count ? starts[position + 1] : lines.count
            var core = Array(lines[(keyLine.index + 1) ..< end])
            var tail: [String] = []
            while let last = core.last, LayoutPreservingEdit.isBlank(last) || last.hasPrefix("#") {
                tail.insert(core.removeLast(), at: 0)
            }
            return LayoutSection(
                key: keyLine.key,
                leading: Array(lines[starts[position] ..< keyLine.index]),
                keyLine: lines[keyLine.index],
                core: core,
                tail: tail
            )
        }
    }

    /// The top-level `key:` lines, or nil if a column-0 line is anything else or a key repeats.
    private static func keyLines(in lines: [String]) -> [(index: Int, key: String)]? {
        var keyLines: [(index: Int, key: String)] = []
        for (index, line) in lines.enumerated() {
            guard let first = line.first, first != " ", first != "#" else { continue }
            if line.hasPrefix("---") || line.hasPrefix("...") || first == "\t" { return nil }
            if first == "-" {
                // An indentless list item belongs to the key above; one before any key
                // makes the whole document a list.
                guard !keyLines.isEmpty else { return nil }
                continue
            }
            guard let key = LayoutPreservingEdit.topLevelKey(in: line) else { return nil }
            keyLines.append((index, key))
        }
        guard !keyLines.isEmpty, Set(keyLines.map(\.key)).count == keyLines.count else { return nil }
        return keyLines
    }
}

/// The line-level editing behind `serialize(_:preservingLayoutOf:)`.
enum LayoutPreservingEdit {
    // MARK: - Editing

    /// `existing` with every section edited to hold the value it has in `regenerated`;
    /// sections only `regenerated` has are appended. Nil when either text isn't a plain
    /// block mapping.
    static func text(editing existing: String, toMatch regenerated: String) -> String? {
        guard var document = LayoutDocument(existing), let target = LayoutDocument(regenerated) else { return nil }
        let targetSections = Dictionary(uniqueKeysWithValues: target.sections.map { ($0.key, $0) })
        let existingKeys = Set(document.sections.map(\.key))
        // Blank lines between sections are the file's style if any section but the last ends
        // with one; new sections follow it.
        let separatesSections = document.sections.dropLast().contains { $0.tail.contains(where: isBlank) }

        var sections = document.sections.compactMap { section in
            targetSections[section.key].map { edit(section, toMatch: $0) }
        }
        for section in target.sections where !existingKeys.contains(section.key) {
            if separatesSections, let last = sections.indices.last, !sections[last].tail.contains(where: isBlank) {
                sections[last].tail.append("")
            }
            sections.append(section)
        }
        document.sections = sections
        return document.text
    }

    /// `section` changed as little as possible to hold `target`'s value.
    private static func edit(_ section: LayoutSection, toMatch target: LayoutSection) -> LayoutSection {
        let current = value(of: section)
        let wanted = value(of: target)
        if sameValue(current, wanted) {
            return section
        }
        let candidates = [
            editedList(section, toMatch: target, current: current, wanted: wanted),
            editedMapping(section, toMatch: target, current: current, wanted: wanted)
        ]
        for case let candidate? in candidates where sameValue(value(of: candidate), wanted) {
            return candidate
        }
        // Regenerate the value, but keep the comments around it.
        return LayoutSection(
            key: section.key,
            leading: section.leading,
            keyLine: target.keyLine,
            core: target.core,
            tail: section.tail
        )
    }

    /// A list of scalars, edited by dropping the lines of removed items and adding new items
    /// after the last kept one. Comments between items stay where they are. Nil unless the
    /// kept items stay in order and the new ones come last.
    private static func editedList(
        _ section: LayoutSection,
        toMatch target: LayoutSection,
        current: Any,
        wanted: Any
    ) -> LayoutSection? {
        guard let oldItems = current as? [Any], let newItems = wanted as? [Any],
              opensBlock(section.keyLine),
              target.core.count == newItems.count,
              target.core.allSatisfy({ isListItem(content(of: $0)) }),
              let itemLines = itemLineIndices(in: section.core, holding: oldItems) else { return nil }

        var unmatched = newItems
        var kept: [Any] = []
        var dropped: Set<Int> = []
        for (position, index) in itemLines.enumerated() {
            if let match = unmatched.firstIndex(where: { sameValue($0, oldItems[position]) }) {
                unmatched.remove(at: match)
                kept.append(oldItems[position])
            } else {
                dropped.insert(index)
            }
        }
        guard sameValue(kept + unmatched, newItems) else { return nil }
        // A comment directly above a removed item was about that item; left behind, it would
        // read as a note on the next one.
        for index in dropped {
            var above = index - 1
            while above >= 0, content(of: section.core[above]).hasPrefix("#") {
                dropped.insert(above)
                above -= 1
            }
        }

        let indent = itemLines.first.map { indentation(of: section.core[$0]) } ?? "  "
        var edited = section
        edited.core = spliced(
            section.core,
            keeping: { index, line in dropped.contains(index) ? nil : line },
            adding: target.core.suffix(unmatched.count).map { indent + content(of: $0) },
            after: itemLines.last { !dropped.contains($0) }
        )
        return edited
    }

    /// A one-level mapping of scalars, such as a rule's settings, edited by replacing the lines
    /// of changed settings, dropping removed ones and adding new ones after the last kept one.
    private static func editedMapping(
        _ section: LayoutSection,
        toMatch target: LayoutSection,
        current: Any,
        wanted: Any
    ) -> LayoutSection? {
        guard let oldMap = current as? [String: Any], let newMap = wanted as? [String: Any],
              oldMap.values.allSatisfy(isScalar), newMap.values.allSatisfy(isScalar),
              opensBlock(section.keyLine),
              let targetEntries = entryLines(in: target.core), targetEntries.lines.count == newMap.count,
              let entries = entryKeys(in: section.core, holding: oldMap) else { return nil }

        var edited = section
        edited.core = spliced(
            section.core,
            keeping: { index, line in
                guard let key = entries.keys[index] else { return line }
                guard let new = newMap[key] else { return nil }
                if let old = oldMap[key], sameValue(old, new) { return line }
                return targetEntries.lines[key].map { entries.indent + $0 }
            },
            adding: targetEntries.order.filter { oldMap[$0] == nil }
                .compactMap { targetEntries.lines[$0].map { entries.indent + $0 } },
            after: entries.keys.keys.filter { newMap[entries.keys[$0] ?? ""] != nil }.max()
        )
        return edited
    }

    /// `core` with each line kept, replaced or dropped (nil) by `keeping`, and `added` inserted
    /// after the line at `insertAfter` — or at the start when there's none.
    private static func spliced(
        _ core: [String],
        keeping: (Int, String) -> String?,
        adding added: [String],
        after insertAfter: Int?
    ) -> [String] {
        var result = insertAfter == nil ? added : []
        for (index, line) in core.enumerated() {
            if let kept = keeping(index, line) {
                result.append(kept)
            }
            if index == insertAfter {
                result.append(contentsOf: added)
            }
        }
        return result
    }

    /// The indices of a list's item lines, if every other line is blank or a comment and the
    /// items are single-line scalars matching `items` in order.
    private static func itemLineIndices(in core: [String], holding items: [Any]) -> [Int]? {
        var indices: [Int] = []
        for (index, line) in core.enumerated() {
            let text = content(of: line)
            if text.isEmpty || text.hasPrefix("#") { continue }
            guard isListItem(text), indices.count < items.count,
                  let parsed = load(text) as? [Any], parsed.count == 1,
                  sameValue(parsed[0], items[indices.count]) else { return nil }
            indices.append(index)
        }
        return indices.count == items.count ? indices : nil
    }

    /// The key of each single-line `key: value` line of a mapping, keyed by line index, and
    /// their shared indentation — if every other line is blank or a comment and the entries
    /// match `mapping`.
    private static func entryKeys(
        in core: [String],
        holding mapping: [String: Any]
    ) -> (keys: [Int: String], indent: String)? {
        var keys: [Int: String] = [:]
        var indent: String?
        for (index, line) in core.enumerated() {
            let text = content(of: line)
            if text.isEmpty || text.hasPrefix("#") { continue }
            guard indent == nil || indent == indentation(of: line),
                  let entry = load(text) as? [String: Any], entry.count == 1, let pair = entry.first,
                  let old = mapping[pair.key], sameValue(pair.value, old) else { return nil }
            indent = indentation(of: line)
            keys[index] = pair.key
        }
        guard let indent, keys.count == mapping.count else { return nil }
        return (keys, indent)
    }

    /// A regenerated mapping's entry lines, unindented, by key and in order.
    private static func entryLines(in core: [String]) -> (lines: [String: String], order: [String])? {
        var lines: [String: String] = [:]
        var order: [String] = []
        for line in core {
            guard let entry = load(content(of: line)) as? [String: Any], entry.count == 1,
                  let key = entry.keys.first else { return nil }
            lines[key] = content(of: line)
            order.append(key)
        }
        return (lines, order)
    }

    // MARK: - Values

    /// A value no other value equals, for a section that doesn't parse.
    private struct Unparseable {}

    /// The value a section gives its key.
    private static func value(of section: LayoutSection) -> Any {
        let text = ([section.keyLine] + section.core).joined(separator: "\n")
        guard let mapping = load(text) as? [String: Any], let value = mapping[section.key] else {
            return Unparseable()
        }
        return value
    }

    /// `yaml` read the way the engine reads a configuration, so `on` stays a string and a
    /// quoted number stays a string — the reading every edit has to preserve.
    static func load(_ yaml: String) -> Any? {
        guard let node = try? Yams.compose(yaml: yaml) else { return nil }
        return try? YAMLConfigurationEngine.nodeToAny(node)
    }

    /// Equality that keeps types apart: `true`, `1` and `1.0` are three different values to
    /// SwiftLint, which rejects a setting of the wrong type.
    static func sameValue(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs as Bool, rhs as Bool):
            return lhs == rhs
        case let (lhs as Int, rhs as Int):
            return lhs == rhs
        case let (lhs as Double, rhs as Double):
            return lhs == rhs
        case let (lhs as String, rhs as String):
            return lhs == rhs
        case let (lhs as [Any], rhs as [Any]):
            return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { sameValue($0, $1) }
        case let (lhs as [String: Any], rhs as [String: Any]):
            return lhs.count == rhs.count && lhs.allSatisfy { key, value in
                rhs[key].map { sameValue(value, $0) } ?? false
            }
        default:
            return false
        }
    }

    // MARK: - Lines

    /// The key of a top-level `key:` line, unquoted; nil for anything else, such as a flow
    /// mapping or a complex key.
    static func topLevelKey(in line: String) -> String? {
        guard let first = line.first, !"{[?&*!|>%@`".contains(first),
              let colon = line.range(of: #":(\s|$)"#, options: .regularExpression) else { return nil }
        var key = String(line[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
        if key.count >= 2, let quote = key.first, quote == "\"" || quote == "'", key.last == quote {
            key = String(key.dropFirst().dropLast())
        }
        return key.isEmpty ? nil : key
    }

    /// Whether a key line leaves its value to the lines below: nothing after the colon but
    /// perhaps a comment.
    private static func opensBlock(_ keyLine: String) -> Bool {
        guard let colon = keyLine.range(of: #":(\s|$)"#, options: .regularExpression) else { return false }
        let rest = keyLine[colon.upperBound...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty || rest.hasPrefix("#")
    }

    private static func isListItem(_ text: String) -> Bool {
        text == "-" || text.hasPrefix("- ")
    }

    private static func isScalar(_ value: Any) -> Bool {
        !(value is [Any]) && !(value is [String: Any])
    }

    static func isBlank(_ line: String) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }

    private static func indentation(of line: String) -> String {
        String(line.prefix { $0 == " " })
    }

    private static func content(of line: String) -> String {
        String(line.drop { $0 == " " })
    }
}
