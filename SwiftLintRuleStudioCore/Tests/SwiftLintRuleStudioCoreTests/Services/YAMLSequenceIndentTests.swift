//
//  YAMLSequenceIndentTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The pass that indents Yams's block sequences under their keys must move each item
//  whole. It moved only the `- ` line, so a list of mappings such as
//  `number_separator.exclude_ranges` came out as invalid YAML and SwiftLint fell back to
//  its default configuration, ignoring `included` and `excluded` (issue #83's symptom).
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing
import Yams

@MainActor
struct YAMLSequenceIndentTests {

    /// The document `yaml` holds, compared as plain values.
    private func value(of yaml: String) throws -> NSObject? {
        try Yams.load(yaml: yaml) as? NSObject
    }

    private func expectSameDocument(
        _ input: String,
        _ output: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let before = try value(of: input)
        let after = try value(of: output)
        #expect(before != nil, sourceLocation: sourceLocation)
        #expect(before == after, "re-indenting changed the document:\n\(output)", sourceLocation: sourceLocation)
    }

    @Test("a list of mappings moves whole, so every key of an item stays under the first")
    func listOfMappings() throws {
        let yams = """
        number_separator:
          exclude_ranges:
          - max: 2030
            min: 1900
          - max: 99
            min: 10
          minimum_length: 3
        """
        let indented = YAMLConfigurationEngine.indentBlockSequences(in: yams)

        #expect(indented == """
        number_separator:
          exclude_ranges:
            - max: 2030
              min: 1900
            - max: 99
              min: 10
          minimum_length: 3
        """)
        try expectSameDocument(yams, indented)
    }

    @Test("a sequence inside an item lands two columns under its own key")
    func sequenceInAnItem() throws {
        let yams = """
        custom_rules:
          no_print:
            included:
            - Sources
            match_kinds:
            - identifier
        list:
        - name: a
          tags:
          - x
          - y
        - name: b
        """
        let indented = YAMLConfigurationEngine.indentBlockSequences(in: yams)

        #expect(indented.contains("\n  - name: a\n    tags:\n      - x\n      - y\n  - name: b"))
        try expectSameDocument(yams, indented)
    }

    @Test("a sequence of sequences keeps its inner items in line")
    func sequenceOfSequences() throws {
        let yams = """
        pairs:
        - - a
          - b
        - - c
        """
        let indented = YAMLConfigurationEngine.indentBlockSequences(in: yams)

        #expect(indented == "pairs:\n  - - a\n    - b\n  - - c")
        try expectSameDocument(yams, indented)
    }

    @Test("a block scalar's text is moved with it, even a line that starts with a dash")
    func blockScalarText() throws {
        let yams = """
        custom_rules:
          rule:
            message: |-
              Prefer:
              - one thing
              - another
            regex: x
        items:
        - |-
          text
          - not an item
        """
        let indented = YAMLConfigurationEngine.indentBlockSequences(in: yams)

        try expectSameDocument(yams, indented)
        #expect(indented.contains("      - one thing\n      - another\n"))
    }

    @Test("plain lists keep the two-column style they had")
    func plainLists() throws {
        let yams = "disabled_rules:\n- todo\n- force_cast\nline_length: 120"
        let indented = YAMLConfigurationEngine.indentBlockSequences(in: yams)

        #expect(indented == "disabled_rules:\n  - todo\n  - force_cast\nline_length: 120")
        try expectSameDocument(yams, indented)
    }

    @Test("a config with exclude_ranges saves as YAML SwiftLint reads, with the ranges intact")
    func excludeRangesRoundTrip() throws {
        let yaml = """
        opt_in_rules:
          - number_separator
        number_separator:
          minimum_length: 3
          exclude_ranges:
            - min: 1900
              max: 2030
        """
        var config = try YAMLConfigurationEngine.parse(yaml)
        config.enableRule("explicit_top_level_acl", kind: .optIn)

        let saved = try YAMLConfigurationEngine.serialize(config)
        let document = try #require(try Yams.load(yaml: saved) as? [String: Any], "saved:\n\(saved)")
        let rule = try #require(document["number_separator"] as? [String: Any])
        let ranges = try #require(rule["exclude_ranges"] as? [[String: Any]])
        #expect(ranges.count == 1)
        #expect(ranges.first?["min"] as? Int == 1_900)
        #expect(ranges.first?["max"] as? Int == 2_030)
        #expect(rule["minimum_length"] as? Int == 3)
    }
}
