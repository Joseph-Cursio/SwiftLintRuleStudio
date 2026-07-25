//
//  ParseParametersPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for `RuleParameterParser.parseParameters` — candidate §7.
//
//  There is no serializer back to `swiftlint rules <id>` output, so there is no
//  round-trip and the laws are metamorphic: change the *input* in a way that
//  should not matter, and demand the output not move.
//
//  The roadmap listed this as blocked on widening `private` helpers
//  (`orderedTopLevelKeys`, `keyName`, `buildParameter`, `isYAMLBool`). It is not.
//  That blocker came from `swift-infer`'s "not reachable from a test" note, which
//  is about the tool wanting to CALL each seeded function directly — a different
//  thing from a law needing it. Every law below is observable at the public
//  boundary through `parseParameters`, so nothing was widened: the parser keeps
//  its encapsulation and the laws still bind, which is the better outcome of the
//  two.
//
//  Generators build CLI blocks from a small key alphabet so keys repeat across
//  trials and ordering collisions actually occur.
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

/// One generated parameter line, kept to primitives for the generator boundary.
private struct ParameterLine: Sendable {
    let nameIndex: Int
    /// 0 = int, 1 = bool, 2 = string, 3 = empty list, 4 = nested mapping.
    let valueKind: Int
}

@MainActor
@Suite("parseParameters property laws")
struct ParseParametersPropertyLawTests {

    nonisolated private static let ruleId = "cyclomatic_complexity"
    nonisolated private static let parameterNames = ["warning", "error", "ignores_case_statements", "severity"]

    nonisolated private static func linesGenerator()
    -> Generator<[ParameterLine], some SendableSequenceType> {
        zip(
            Gen<Int>.int(in: 0 ... (parameterNames.count - 1)),
            Gen<Int>.int(in: 0...4)
        )
        .map { ParameterLine(nameIndex: $0, valueKind: $1) }
        .array(of: 0...4)
    }

    // MARK: - Rendering

    /// The source line(s) for one parameter, at the wrapper's child indent.
    /// A nested mapping occupies a second, deeper-indented line — which is the
    /// shape `buildParameter` refuses, and `keyName` skips.
    nonisolated private static func sourceLines(for line: ParameterLine, name: String) -> [String] {
        switch line.valueKind {
        case 0: return ["    \(name): 10"]
        case 1: return ["    \(name): false"]
        case 2: return ["    \(name): alpha"]
        case 3: return ["    \(name): []"]
        default: return ["    \(name):", "      nested: 1"]
        }
    }

    /// Render a `swiftlint rules <id>` transcript around the generated block.
    /// De-duplicated by name, first-wins, so the source stays valid YAML.
    ///
    /// Note there are no blank lines *inside* the block: a blank line after
    /// content terminates it (`extractYAMLBlock`), which is a contract this
    /// suite pins separately rather than something the comment law may assume.
    nonisolated private static func render(_ lines: [ParameterLine], commented: Bool) -> String {
        var seen: [String] = []
        var body: [String] = []
        for line in lines {
            let name = parameterNames[line.nameIndex]
            guard !seen.contains(name) else { continue }
            seen.append(name)
            if commented {
                body.append("    # a comment about \(name)")
            }
            body.append(contentsOf: sourceLines(for: line, name: name))
        }
        return """
        Rule: Cyclomatic Complexity

        Configuration (YAML):
          \(ruleId):
        \(body.joined(separator: "\n"))

        Triggering Examples (violations are marked with '↓'):

        Example #1
        """
    }

    /// The names that survive parsing: `severity` is handled by the severity
    /// picker and dropped here, and a nested mapping is not representable by the
    /// flat `RuleParameter` model.
    nonisolated private static func expectedNames(_ lines: [ParameterLine]) -> [String] {
        var seen: [String] = []
        var kept: [String] = []
        for line in lines {
            let name = parameterNames[line.nameIndex]
            guard !seen.contains(name) else { continue }
            seen.append(name)
            guard name != "severity", line.valueKind != 4 else { continue }
            kept.append(name)
        }
        return kept
    }

    // MARK: - Metamorphic laws

    @Test("comment lines do not change the parsed parameters")
    func commentInsensitivity() async {
        await propertyCheck(input: Self.linesGenerator()) { lines in
            let plain = RuleParameterParser.parseParameters(
                from: Self.render(lines, commented: false), ruleId: Self.ruleId
            )
            let commented = RuleParameterParser.parseParameters(
                from: Self.render(lines, commented: true), ruleId: Self.ruleId
            )

            #expect(plain?.map(\.name) == commented?.map(\.name))
            #expect(plain?.map(\.type) == commented?.map(\.type))
        }
    }

    @Test("parameters come back in source order, dropping severity and nested mappings")
    func sourceOrderAndDrops() async {
        await propertyCheck(input: Self.linesGenerator()) { lines in
            let parsed = RuleParameterParser.parseParameters(
                from: Self.render(lines, commented: false), ruleId: Self.ruleId
            )
            let expected = Self.expectedNames(lines)

            // nil and [] are the same claim here: the parser returns nil rather
            // than an empty array when nothing survives.
            #expect((parsed ?? []).map(\.name) == expected)
        }
    }

    @Test("permuting the source lines permutes the output the same way")
    func orderIsCarriedFromTheSource() async {
        await propertyCheck(input: Self.linesGenerator()) { lines in
            // Permute a list with no repeated NAMES. With repeats, reversing is
            // not a permutation of the parsed input at all: the renderer keeps
            // the first entry per name, so reversing can swap in an entry of a
            // different kind and legitimately change the surviving key set. The
            // law is about reordering the same parameters, so make them distinct
            // first.
            var seen: Set<Int> = []
            let distinct = lines.filter { seen.insert($0.nameIndex).inserted }

            let forward = RuleParameterParser.parseParameters(
                from: Self.render(distinct, commented: false), ruleId: Self.ruleId
            ) ?? []
            let backward = RuleParameterParser.parseParameters(
                from: Self.render(distinct.reversed(), commented: false), ruleId: Self.ruleId
            ) ?? []

            // The same parameters survive either way — order is not a filter...
            #expect(Set(forward.map(\.name)) == Set(backward.map(\.name)))
            // ...and the output order tracks the source exactly, so reversing
            // the source reverses the output.
            #expect(backward.map(\.name) == forward.map(\.name).reversed())
        }
    }

    // MARK: - Classification

    @Test("booleans never classify as integers")
    func boolBeforeInt() async {
        // The user-facing contract: a YAML boolean reaches the rule-detail editor
        // as a `.boolean` parameter, never as integer 0/1.
        //
        // MEASURED: this law does NOT currently prove that `isYAMLBool`'s
        // CFBoolean probe is load-bearing. Reordering `buildParameter` to check
        // `Int` first — the exact bug the guard was written against — leaves the
        // suite green, because on Yams 6.2.1 with this toolchain `Yams.load`
        // returns a genuine Swift `Bool` for which `as? Int` is nil. The
        // Foundation number-bridging hazard the guard describes does not
        // manifest here. The guard is correct and cheap, and CFBoolean still
        // identifies the value, so it stays as insurance against a Yams change —
        // but nobody should read a green run as evidence it is doing work.
        await propertyCheck(input: Gen<Bool>.bool, Gen<Bool>.bool) { first, second in
            let output = """
            Configuration (YAML):

              \(Self.ruleId):
                flag_one: \(first)
                flag_two: \(second)
                count: 1

            Triggering Examples (violations are marked with '↓'):
            """
            let parsed = RuleParameterParser.parseParameters(from: output, ruleId: Self.ruleId) ?? []
            let byName = Dictionary(uniqueKeysWithValues: parsed.map { ($0.name, $0) })

            #expect(byName["flag_one"]?.type == .boolean)
            #expect(byName["flag_two"]?.type == .boolean)
            #expect(byName["count"]?.type == .integer)
        }
    }

    // MARK: - Rejection seams

    @Test("a placeholder block is rejected rather than parsed")
    func placeholderRejection() async {
        // SwiftLint emits documentation placeholders for some rules
        // (`{Protocol Name}: {Case Name}: {warning|error}`). Yams fatal-errors on
        // those, so rejection is load-bearing, not cosmetic.
        await propertyCheck(input: Gen<Int>.int(in: 0...2)) { position in
            var body = ["    alpha: 1", "    beta: 2", "    gamma: 3"]
            body.insert("    {Placeholder Name}: {warning|error}", at: position)
            let output = """
            Configuration (YAML):

              \(Self.ruleId):
            \(body.joined(separator: "\n"))

            Triggering Examples (violations are marked with '↓'):
            """

            #expect(RuleParameterParser.parseParameters(from: output, ruleId: Self.ruleId) == nil)
        }
    }

    @Test("a blank line ends the block — it does not survive as whitespace")
    func blankLineTerminatesTheBlock() {
        // The roadmap stated this law as "comment lines OR BLANK LINES don't
        // change the parsed set". The blank-line half is false, and writing the
        // law is what surfaced it: `extractYAMLBlock` treats a blank line after
        // content as the end of the section, because that is how SwiftLint
        // separates `Configuration (YAML):` from `Triggering Examples:`.
        //
        // So a blank line is not whitespace to be ignored — it is a terminator,
        // and everything after it is invisible. Pinned because a future "tidy
        // up the parser" change could plausibly start skipping blanks and would
        // then swallow the following section as configuration.
        let output = """
        Configuration (YAML):
          \(Self.ruleId):
            warning: 10

            error: 20

        Triggering Examples (violations are marked with '↓'):
        """
        let parsed = RuleParameterParser.parseParameters(from: output, ruleId: Self.ruleId) ?? []
        #expect(parsed.map(\.name) == ["warning"])
    }

    @Test("output with no Configuration block yields nil")
    func missingBlockYieldsNil() {
        let output = """
        Rule: Cyclomatic Complexity

        Triggering Examples (violations are marked with '↓'):

        Example #1
        """
        #expect(RuleParameterParser.parseParameters(from: output, ruleId: Self.ruleId) == nil)
    }
}
