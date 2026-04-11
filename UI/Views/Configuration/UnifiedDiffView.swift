//
//  UnifiedDiffView.swift
//  SwiftLintRuleStudio
//
//  Line-by-line unified diff view with GitHub-style green/red highlighting
//  and character-level emphasis on the specific characters that differ
//

import SwiftUI

// MARK: - Diff Line Types

/// A span within a line, either highlighted (changed) or normal
struct DiffSpan {
    let text: String
    let isHighlighted: Bool
}

struct DiffLine {
    enum Kind {
        case added
        case removed
        case unchanged
    }

    let text: String
    let kind: Kind
    /// Character-level spans for inline highlighting (nil = no inline diff)
    var spans: [DiffSpan]?

    var prefix: String {
        switch kind {
        case .added: "+"
        case .removed: "−"
        case .unchanged: " "
        }
    }

    var backgroundColor: Color {
        switch kind {
        case .added: Color.green.opacity(0.12)
        case .removed: Color.red.opacity(0.12)
        case .unchanged: .clear
        }
    }

    var highlightColor: Color {
        switch kind {
        case .added: Color.green.opacity(0.3)
        case .removed: Color.red.opacity(0.3)
        case .unchanged: .clear
        }
    }

    var prefixColor: Color {
        switch kind {
        case .added: .green
        case .removed: .red
        case .unchanged: .secondary
        }
    }
}

// MARK: - Unified Diff Content View

struct UnifiedDiffContentView: View {
    let before: String
    let after: String
    var beforeLabel: String = "Before"
    var afterLabel: String = "After"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                diffLegend
                Divider()
                diffLinesList
            }
        }
    }

    private var diffLegend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 12, height: 12)
                Text(beforeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 12, height: 12)
                Text(afterLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var diffLinesList: some View {
        let diffLines = UnifiedDiffEngine.computeDiff(
            before: before,
            after: after
        )

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                DiffLineView(line: line)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Diff Line View

struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            Text(line.prefix)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(line.prefixColor)
                .frame(width: 20, alignment: .center)

            lineContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
        .background(line.backgroundColor)
    }

    @ViewBuilder
    private var lineContent: some View {
        if let spans = line.spans, !spans.isEmpty {
            // Render with character-level highlighting using HStack of segments
            HStack(spacing: 0) {
                ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                    Text(span.text)
                        .font(.system(.body, design: .monospaced))
                        .background(span.isHighlighted ? line.highlightColor : .clear)
                }
            }
        } else {
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(.body, design: .monospaced))
        }
    }
}

// MARK: - LCS Diff Algorithm

enum UnifiedDiffEngine {
    static func computeDiff(before: String, after: String) -> [DiffLine] {
        let oldLines = before.components(separatedBy: .newlines)
        let newLines = after.components(separatedBy: .newlines)

        let lcsTable = buildLCSTable(oldLines, newLines)
        var rawLines = buildDiffLines(oldLines, newLines, lcsTable)

        // Post-process: add character-level highlights to paired changed lines
        addInlineHighlights(&rawLines)

        return rawLines
    }

    // MARK: Line-level LCS

    private static func buildLCSTable(_ oldLines: [String], _ newLines: [String]) -> [[Int]] {
        let rowCount = oldLines.count + 1
        let colCount = newLines.count + 1
        var table = Array(repeating: Array(repeating: 0, count: colCount), count: rowCount)

        for idx in 1..<rowCount {
            for jdx in 1..<colCount {
                if oldLines[idx - 1] == newLines[jdx - 1] {
                    table[idx][jdx] = table[idx - 1][jdx - 1] + 1
                } else {
                    table[idx][jdx] = max(table[idx - 1][jdx], table[idx][jdx - 1])
                }
            }
        }
        return table
    }

    private static func buildDiffLines(
        _ oldLines: [String],
        _ newLines: [String],
        _ table: [[Int]]
    ) -> [DiffLine] {
        var result: [DiffLine] = []
        var idx = oldLines.count
        var jdx = newLines.count

        while idx > 0 || jdx > 0 {
            if idx > 0 && jdx > 0 && oldLines[idx - 1] == newLines[jdx - 1] {
                result.append(DiffLine(text: oldLines[idx - 1], kind: .unchanged))
                idx -= 1
                jdx -= 1
            } else if jdx > 0 && (idx == 0 || table[idx][jdx - 1] >= table[idx - 1][jdx]) {
                result.append(DiffLine(text: newLines[jdx - 1], kind: .added))
                jdx -= 1
            } else if idx > 0 {
                result.append(DiffLine(text: oldLines[idx - 1], kind: .removed))
                idx -= 1
            }
        }

        return result.reversed()
    }

    // MARK: Character-level inline highlights

    /// Find adjacent removed+added line groups and compute character-level diffs
    private static func addInlineHighlights(_ lines: inout [DiffLine]) {
        var idx = 0
        while idx < lines.count {
            // Collect a run of removed lines
            var removedStart = idx
            while removedStart < lines.count && lines[removedStart].kind == .removed {
                removedStart += 1
            }
            let removedCount = removedStart - idx

            // Collect the immediately following run of added lines
            var addedEnd = removedStart
            while addedEnd < lines.count && lines[addedEnd].kind == .added {
                addedEnd += 1
            }
            let addedCount = addedEnd - removedStart

            if removedCount > 0 && addedCount > 0 {
                // Pair them up one-to-one (like GitHub does)
                let pairCount = min(removedCount, addedCount)
                for pairIdx in 0..<pairCount {
                    let removedLineIdx = idx + pairIdx
                    let addedLineIdx = removedStart + pairIdx
                    let (removedSpans, addedSpans) = characterDiff(
                        old: lines[removedLineIdx].text,
                        new: lines[addedLineIdx].text
                    )
                    lines[removedLineIdx].spans = removedSpans
                    lines[addedLineIdx].spans = addedSpans
                }
                idx = addedEnd
            } else if removedCount > 0 {
                idx = removedStart
            } else {
                idx += 1
            }
        }
    }

    /// Compute character-level diff between two strings, returning spans for each
    private static func characterDiff(
        old: String,
        new: String
    ) -> (oldSpans: [DiffSpan], newSpans: [DiffSpan]) {
        let oldChars = Array(old)
        let newChars = Array(new)

        let lcsSet = characterLCS(oldChars, newChars)

        let oldSpans = buildSpans(chars: oldChars, lcsIndices: lcsSet.old)
        let newSpans = buildSpans(chars: newChars, lcsIndices: lcsSet.new)

        return (oldSpans, newSpans)
    }

    /// Returns the LCS index sets for both strings
    private static func characterLCS(
        _ oldChars: [Character],
        _ newChars: [Character]
    ) -> (old: Set<Int>, new: Set<Int>) {
        let rowCount = oldChars.count + 1
        let colCount = newChars.count + 1
        var table = Array(repeating: Array(repeating: 0, count: colCount), count: rowCount)

        for idx in 1..<rowCount {
            for jdx in 1..<colCount {
                if oldChars[idx - 1] == newChars[jdx - 1] {
                    table[idx][jdx] = table[idx - 1][jdx - 1] + 1
                } else {
                    table[idx][jdx] = max(table[idx - 1][jdx], table[idx][jdx - 1])
                }
            }
        }

        // Backtrack to find which indices are part of the LCS
        var oldIndices = Set<Int>()
        var newIndices = Set<Int>()
        var idx = oldChars.count
        var jdx = newChars.count

        while idx > 0 && jdx > 0 {
            if oldChars[idx - 1] == newChars[jdx - 1] {
                oldIndices.insert(idx - 1)
                newIndices.insert(jdx - 1)
                idx -= 1
                jdx -= 1
            } else if table[idx - 1][jdx] > table[idx][jdx - 1] {
                idx -= 1
            } else {
                jdx -= 1
            }
        }

        return (oldIndices, newIndices)
    }

    /// Build spans from characters, grouping consecutive highlighted/normal characters
    private static func buildSpans(chars: [Character], lcsIndices: Set<Int>) -> [DiffSpan] {
        guard !chars.isEmpty else { return [] }

        var spans: [DiffSpan] = []
        var currentText = ""
        var currentHighlighted = !lcsIndices.contains(0)

        for (charIdx, char) in chars.enumerated() {
            let isHighlighted = !lcsIndices.contains(charIdx)

            if isHighlighted == currentHighlighted {
                currentText.append(char)
            } else {
                if !currentText.isEmpty {
                    spans.append(DiffSpan(text: currentText, isHighlighted: currentHighlighted))
                }
                currentText = String(char)
                currentHighlighted = isHighlighted
            }
        }

        if !currentText.isEmpty {
            spans.append(DiffSpan(text: currentText, isHighlighted: currentHighlighted))
        }

        return spans
    }
}
