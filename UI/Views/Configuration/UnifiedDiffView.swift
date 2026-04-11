//
//  UnifiedDiffView.swift
//  SwiftLintRuleStudio
//
//  Line-by-line unified diff view with green/red highlighting
//

import SwiftUI

// MARK: - Diff Line Types

struct DiffLine {
    enum Kind {
        case added
        case removed
        case unchanged
    }

    let text: String
    let kind: Kind

    var prefix: String {
        switch kind {
        case .added: "+"
        case .removed: "−"
        case .unchanged: " "
        }
    }

    var backgroundColor: Color {
        switch kind {
        case .added: Color.green.opacity(0.15)
        case .removed: Color.red.opacity(0.15)
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
                // Legend
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 12, height: 12)
                        Text(beforeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 12, height: 12)
                        Text(afterLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                let diffLines = UnifiedDiffEngine.computeDiff(
                    before: before,
                    after: after
                )

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                        DiffLineView(line: line)
                    }
                }
                .padding(.vertical, 4)
            }
        }
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

            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
        .background(line.backgroundColor)
    }
}

// MARK: - LCS Diff Algorithm

enum UnifiedDiffEngine {
    static func computeDiff(before: String, after: String) -> [DiffLine] {
        let oldLines = before.components(separatedBy: .newlines)
        let newLines = after.components(separatedBy: .newlines)

        let lcsTable = buildLCSTable(oldLines, newLines)
        return buildDiffLines(oldLines, newLines, lcsTable)
    }

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
}
