//
//  RuleParameterParserTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Tests that the parser converts canned `swiftlint rules <id>` output
//  into the structured [RuleParameter] consumed by the rule-detail UI.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@Suite("RuleParameterParser")
struct RuleParameterParserTests {

    // MARK: - Cyclomatic Complexity (Int + Int + Bool)

    @Test("parses warning/error Ints and an ignores_case_statements Bool")
    func parsesCyclomaticComplexity() throws {
        let cliOutput = """
        Cyclomatic Complexity (cyclomatic_complexity): Complexity of function bodies should be limited.

        Configuration (YAML):

          cyclomatic_complexity:
            warning: 10
            error: 20
            ignores_case_statements: false

        Triggering Examples (violations are marked with '↓'):

        Example #1
        """

        let params = try #require(
            RuleParameterParser.parseParameters(from: cliOutput, ruleId: "cyclomatic_complexity")
        )

        #expect(params.count == 3)

        let byName = Dictionary(uniqueKeysWithValues: params.map { ($0.name, $0) })
        let warning = try #require(byName["warning"])
        #expect(warning.type == .integer)
        #expect(warning.defaultValue.value as? Int == 10)

        let error = try #require(byName["error"])
        #expect(error.type == .integer)
        #expect(error.defaultValue.value as? Int == 20)

        let ignores = try #require(byName["ignores_case_statements"])
        #expect(ignores.type == .boolean)
        #expect(ignores.defaultValue.value as? Bool == false)
    }

    // MARK: - Line Length (Int + Bool + empty array)

    @Test("parses Ints, Bools, and an empty array")
    func parsesLineLength() throws {
        let cliOutput = """
        Line Length (line_length): Lines should not span too many characters.

        Configuration (YAML):

          line_length:
            warning: 120
            error: 200
            ignores_urls: false
            excluded_lines_patterns: []

        Triggering Examples (violations are marked with '↓'):
        """

        let params = try #require(
            RuleParameterParser.parseParameters(from: cliOutput, ruleId: "line_length")
        )
        let byName = Dictionary(uniqueKeysWithValues: params.map { ($0.name, $0) })

        let warning = try #require(byName["warning"])
        #expect(warning.type == .integer)
        #expect(warning.defaultValue.value as? Int == 120)

        let ignores = try #require(byName["ignores_urls"])
        #expect(ignores.type == .boolean)
        #expect(ignores.defaultValue.value as? Bool == false)

        let excluded = try #require(byName["excluded_lines_patterns"])
        #expect(excluded.type == .array)
        let arrayValue = try #require(excluded.defaultValue.value as? [Any])
        #expect(arrayValue.isEmpty)
    }

    // MARK: - Severity key is filtered

    @Test("top-level severity is filtered (handled by Severity picker)")
    func filtersSeverityKey() throws {
        let cliOutput = """
        Trailing Comma (trailing_comma): Trailing commas in arrays and dictionaries should be avoided/enforced.

        Configuration (YAML):

          trailing_comma:
            severity: warning
            mandatory_comma: false

        Triggering Examples (violations are marked with '↓'):
        """

        let params = try #require(
            RuleParameterParser.parseParameters(from: cliOutput, ruleId: "trailing_comma")
        )
        #expect(params.count == 1)
        #expect(params.first?.name == "mandatory_comma")
        #expect(params.first?.type == .boolean)
    }

    // MARK: - Nested mappings are skipped (not yet supported)

    @Test("nested mappings are skipped, scalars at the same level kept")
    func skipsNestedMappings() throws {
        let cliOutput = """
        Identifier Name (identifier_name): Identifier names should only contain alphanumeric characters.

        Configuration (YAML):

          identifier_name:
            min_length:
              warning: 3
              error: 2
            max_length:
              warning: 40
              error: 60
            excluded: ["^id$"]
            allowed_symbols: []

        Triggering Examples (violations are marked with '↓'):
        """

        let params = try #require(
            RuleParameterParser.parseParameters(from: cliOutput, ruleId: "identifier_name")
        )
        let names = Set(params.map(\.name))
        // min_length and max_length are nested mappings -> skipped
        #expect(!names.contains("min_length"))
        #expect(!names.contains("max_length"))
        // excluded and allowed_symbols are arrays -> kept
        #expect(names.contains("excluded"))
        #expect(names.contains("allowed_symbols"))
    }

    // MARK: - Filled array values are preserved

    @Test("array defaults preserve their string items")
    func preservesArrayDefaults() throws {
        let cliOutput = """
        Some Rule (some_rule): Description.

        Configuration (YAML):

          some_rule:
            excluded: ["^id$", "foo"]

        Triggering Examples (violations are marked with '↓'):
        """

        let params = try #require(
            RuleParameterParser.parseParameters(from: cliOutput, ruleId: "some_rule")
        )
        let excluded = try #require(params.first { $0.name == "excluded" })
        #expect(excluded.type == .array)
        let items = try #require(excluded.defaultValue.value as? [Any])
        #expect(items.count == 2)
        #expect(items[0] as? String == "^id$")
        #expect(items[1] as? String == "foo")
    }

    // MARK: - Placeholder-shaped YAML is rejected (Yams crash regression)

    @Test("placeholder YAML with {Name}: keys returns nil instead of crashing Yams")
    func placeholderYAMLReturnsNil() {
        // Real CLI output for `required_enum_case` — the block is a documentation
        // placeholder, not a real config. Feeding `{Protocol Name}:` to Yams hits
        // a fatalError in Constructor; the parser must reject it pre-Yams.
        let cliOutput = """
        Required Enum Case (required_enum_case): Enums conforming to a protocol must implement specific case(s).

        Configuration (YAML):

          required_enum_case:
            {Protocol Name}:
              {Case Name 1}: {warning|error}
              {Case Name 2}: {warning|error}

        Triggering Examples (violations are marked with '↓'):
        """
        let params = RuleParameterParser.parseParameters(from: cliOutput, ruleId: "required_enum_case")
        #expect(params == nil)
    }

    // MARK: - No Configuration block -> nil

    @Test("returns nil when CLI output has no Configuration block")
    func returnsNilWithoutConfigBlock() {
        let cliOutput = """
        Force Cast (force_cast): Force casts should be avoided.

        Triggering Examples (violations are marked with '↓'):

        Example #1
        """
        let params = RuleParameterParser.parseParameters(from: cliOutput, ruleId: "force_cast")
        #expect(params == nil)
    }

    // MARK: - Source order is preserved

    @Test("parameter order matches source order, not dictionary order")
    func preservesSourceOrder() throws {
        let cliOutput = """
        Configuration (YAML):

          some_rule:
            zebra: 1
            alpha: 2
            mango: 3
        """
        let params = try #require(
            RuleParameterParser.parseParameters(from: cliOutput, ruleId: "some_rule")
        )
        #expect(params.map(\.name) == ["zebra", "alpha", "mango"])
    }
}
