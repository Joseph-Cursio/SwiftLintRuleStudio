//
//  UnifiedDiffEngineTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for the LCS diff algorithm and character-level highlighting
//

import Testing
import Foundation
import SwiftUI
@testable import SwiftLintRuleStudio
import LintStudioCore
import LintStudioUI

@MainActor
@Suite("UnifiedDiffEngine Tests")
struct UnifiedDiffEngineTests {

    // MARK: - Identical Content

    @Test("Identical strings produce only unchanged lines")
    func identicalStrings() {
        let text = "line one\nline two\nline three"
        let diff = UnifiedDiffEngine.computeDiff(before: text, after: text)

        #expect(diff.count == 3)
        for diffLine in diff {
            #expect(diffLine.kind == .unchanged)
        }
    }

    @Test("Empty strings produce empty diff")
    func emptyStrings() {
        let diff = UnifiedDiffEngine.computeDiff(before: "", after: "")
        // An empty string split by newlines gives [""], so 1 unchanged line
        #expect(diff.count == 1)
        #expect(diff[0].kind == .unchanged)
        #expect(diff[0].text.isEmpty)
    }

    // MARK: - Simple Additions

    @Test("Adding a line at the end produces an added diff line")
    func addLineAtEnd() {
        let before = "line one\nline two"
        let after = "line one\nline two\nline three"
        let diff = UnifiedDiffEngine.computeDiff(before: before, after: after)

        let addedLines = diff.filter { $0.kind == .added }
        #expect(addedLines.count == 1)
        #expect(addedLines[0].text == "line three")

        let unchangedLines = diff.filter { $0.kind == .unchanged }
        #expect(unchangedLines.count == 2)
    }

    @Test("Adding a line at the beginning produces an added diff line")
    func addLineAtBeginning() {
        let before = "line two\nline three"
        let after = "line one\nline two\nline three"
        let diff = UnifiedDiffEngine.computeDiff(before: before, after: after)

        let addedLines = diff.filter { $0.kind == .added }
        #expect(addedLines.count == 1)
        #expect(addedLines[0].text == "line one")
    }

    @Test("Adding multiple lines produces correct added lines")
    func addMultipleLines() {
        let before = "alpha"
        let after = "alpha\nbeta\ngamma"
        let diff = UnifiedDiffEngine.computeDiff(before: before, after: after)

        let addedLines = diff.filter { $0.kind == .added }
        #expect(addedLines.count == 2)
    }

    // MARK: - Simple Removals

    @Test("Removing a line produces a removed diff line")
    func removeLine() {
        let before = "line one\nline two\nline three"
        let after = "line one\nline three"
        let diff = UnifiedDiffEngine.computeDiff(before: before, after: after)

        let removedLines = diff.filter { $0.kind == .removed }
        #expect(removedLines.count == 1)
        #expect(removedLines[0].text == "line two")
    }

    @Test("Removing all lines produces only removed lines")
    func removeAllLines() {
        let before = "line one\nline two"
        let after = ""
        let diff = UnifiedDiffEngine.computeDiff(before: before, after: after)

        let removedLines = diff.filter { $0.kind == .removed }
        #expect(removedLines.count == 2)

        // After is empty, which splits to [""], giving 1 added empty line
        let addedLines = diff.filter { $0.kind == .added }
        #expect(addedLines.count == 1)
        #expect(addedLines[0].text.isEmpty)
    }

    // MARK: - Modifications

    @Test("Modified line produces a removed and an added line")
    func modifiedLine() {
        let before = "let count = 10"
        let after = "let count = 20"
        let diff = UnifiedDiffEngine.computeDiff(before: before, after: after)

        let removedLines = diff.filter { $0.kind == .removed }
        let addedLines = diff.filter { $0.kind == .added }

        #expect(removedLines.count == 1)
        #expect(addedLines.count == 1)
        #expect(removedLines[0].text == "let count = 10")
        #expect(addedLines[0].text == "let count = 20")
    }

    @Test("Multiple modified lines produce paired removed/added lines")
    func multipleModifiedLines() {
        let before = "alpha\nbeta\ngamma"
        let after = "alpha\nBETA\nGAMMA"
        let diff = UnifiedDiffEngine.computeDiff(before: before, after: after)

        let unchangedLines = diff.filter { $0.kind == .unchanged }
        let removedLines = diff.filter { $0.kind == .removed }
        let addedLines = diff.filter { $0.kind == .added }

        #expect(unchangedLines.count == 1)
        #expect(unchangedLines[0].text == "alpha")
        #expect(removedLines.count == 2)
        #expect(addedLines.count == 2)
    }

    // MARK: - Character-Level Highlighting

    @Test("Character-level diff highlights changed characters in paired lines")
    func characterLevelHighlighting() {
        let before = "let value = 10"
        let after = "let value = 20"
        let diff = UnifiedDiffEngine.computeDiff(before: before, after: after)

        let removedLine = diff.first { $0.kind == .removed }
        let addedLine = diff.first { $0.kind == .added }

        // Both should have spans for character-level highlighting
        #expect(removedLine?.spans != nil)
        #expect(addedLine?.spans != nil)

        // The "1" in "10" vs "2" in "20" should be highlighted
        if let spans = removedLine?.spans {
            let highlightedText = spans.filter(\.isHighlighted).map(\.text).joined()
            #expect(highlightedText.contains("1"))
        }

        if let spans = addedLine?.spans {
            let highlightedText = spans.filter(\.isHighlighted).map(\.text).joined()
            #expect(highlightedText.contains("2"))
        }
    }

    @Test("Unchanged lines have no character-level spans")
    func unchangedLinesNoSpans() {
        let text = "unchanged line"
        let diff = UnifiedDiffEngine.computeDiff(before: text, after: text)

        #expect(diff[0].spans == nil)
    }

    @Test("Completely different paired lines highlight all characters")
    func completelyDifferentLines() {
        let before = "abc"
        let after = "xyz"
        let diff = UnifiedDiffEngine.computeDiff(before: before, after: after)

        let removedLine = diff.first { $0.kind == .removed }
        if let spans = removedLine?.spans {
            let allHighlighted = spans.allSatisfy(\.isHighlighted)
            #expect(allHighlighted)
        }
    }

    // MARK: - DiffLine Properties

    @Test("Added line has correct prefix")
    func addedLinePrefix() {
        let line = DiffLine(text: "new line", kind: .added)
        #expect(line.prefix == "+")
    }

    @Test("Removed line has correct prefix")
    func removedLinePrefix() {
        let line = DiffLine(text: "old line", kind: .removed)
        #expect(line.prefix == "\u{2212}") // minus sign
    }

    @Test("Unchanged line has space prefix")
    func unchangedLinePrefix() {
        let line = DiffLine(text: "same line", kind: .unchanged)
        #expect(line.prefix == " ")
    }

    @Test("Added line has green background")
    func addedLineBackground() {
        let line = DiffLine(text: "new", kind: .added)
        #expect(line.backgroundColor != .clear)
    }

    @Test("Removed line has red background")
    func removedLineBackground() {
        let line = DiffLine(text: "old", kind: .removed)
        #expect(line.backgroundColor != .clear)
    }

    @Test("Unchanged line has clear background")
    func unchangedLineBackground() {
        let line = DiffLine(text: "same", kind: .unchanged)
        #expect(line.backgroundColor == .clear)
    }

    // MARK: - DiffSpan Tests

    @Test("DiffSpan stores text and highlight state")
    func diffSpanProperties() {
        let highlighted = DiffSpan(text: "changed", isHighlighted: true)
        let normal = DiffSpan(text: "same", isHighlighted: false)

        #expect(highlighted.text == "changed")
        #expect(highlighted.isHighlighted == true)
        #expect(normal.text == "same")
        #expect(normal.isHighlighted == false)
    }

    // MARK: - Complex Scenarios

    @Test("Mixed additions, removals, and unchanged lines")
    func mixedChanges() {
        let before = """
        line one
        line two
        line three
        line four
        """
        let after = """
        line one
        line TWO
        line three
        line five
        line six
        """
        let diff = UnifiedDiffEngine.computeDiff(before: before, after: after)

        let unchangedTexts = diff.filter { $0.kind == .unchanged }.map(\.text)
        let removedTexts = diff.filter { $0.kind == .removed }.map(\.text)
        let addedTexts = diff.filter { $0.kind == .added }.map(\.text)

        // "line one" and "line three" should be unchanged
        #expect(unchangedTexts.contains("line one"))
        #expect(unchangedTexts.contains("line three"))

        // "line two" removed, "line TWO" added
        #expect(removedTexts.contains("line two"))
        #expect(addedTexts.contains("line TWO"))

        // "line four" removed, "line five" and "line six" added
        #expect(removedTexts.contains("line four"))
        #expect(addedTexts.contains("line five"))
        #expect(addedTexts.contains("line six"))
    }

    @Test("YAML config diff produces correct changes")
    func yamlConfigDiff() {
        let before = """
        disabled_rules:
          - force_cast
          - line_length
        opt_in_rules:
          - empty_count
        """
        let after = """
        disabled_rules:
          - force_cast
        opt_in_rules:
          - empty_count
          - explicit_init
        """
        let diff = UnifiedDiffEngine.computeDiff(before: before, after: after)

        let removedTexts = diff.filter { $0.kind == .removed }.map(\.text)
        let addedTexts = diff.filter { $0.kind == .added }.map(\.text)

        #expect(removedTexts.contains("  - line_length"))
        #expect(addedTexts.contains("  - explicit_init"))
    }

    // MARK: - Highlight Color Tests

    @Test("Added line highlight color is non-clear")
    func addedHighlightColor() {
        let line = DiffLine(text: "new", kind: .added)
        #expect(line.highlightColor != .clear)
    }

    @Test("Removed line highlight color is non-clear")
    func removedHighlightColor() {
        let line = DiffLine(text: "old", kind: .removed)
        #expect(line.highlightColor != .clear)
    }

    @Test("Unchanged line highlight color is clear")
    func unchangedHighlightColor() {
        let line = DiffLine(text: "same", kind: .unchanged)
        #expect(line.highlightColor == .clear)
    }

    // MARK: - Prefix Color Tests

    @Test("Added line prefix color is green")
    func addedPrefixColor() {
        let line = DiffLine(text: "new", kind: .added)
        #expect(line.prefixColor == .green)
    }

    @Test("Removed line prefix color is red")
    func removedPrefixColor() {
        let line = DiffLine(text: "old", kind: .removed)
        #expect(line.prefixColor == .red)
    }

    @Test("Unchanged line prefix color is secondary")
    func unchangedPrefixColor() {
        let line = DiffLine(text: "same", kind: .unchanged)
        #expect(line.prefixColor == .secondary)
    }
}
