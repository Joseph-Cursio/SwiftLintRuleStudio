//
//  RuleRegistryDetailsFallbackTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  A rule's details when the generated docs give nothing, read from
//  `swiftlint rules <id>`. The fixture is that command's real output
//  (SwiftLint 0.65.1): a blank line after each header, and each example
//  numbered. The parser used to end a section at every flush, so the blank line
//  after a header ended it before the first example, and real output yielded
//  no examples at all.
//

@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct RuleRegistryDetailsFallbackTests {

    private static let realDetail = """
        Force Cast (force_cast): Force casts should be avoided

        Configuration (YAML):

          force_cast:
            severity: error

        Triggering Examples (violations are marked with '↓'):

        Example #1

            NSNumber() ↓as! Int

        Example #2

            let configuration = Configuration()
            let value = configuration ↓as! Int

        Non-Triggering Examples:

        Example #1

            NSNumber() as? Int
        """

    private static func rule(docs: String, detail: String) async throws -> Rule {
        try await RuleRegistry.fetchRuleDetailsHelper(
            identifier: "force_cast",
            category: .idiomatic,
            isOptIn: false,
            swiftLintCLI: RuleDetailsSwiftLintCLIActor(docs: docs, detail: detail)
        )
    }

    @Test("every example in real `swiftlint rules` output is read, in its section")
    @MainActor
    func realOutputExamples() async throws {
        let rule = try await Self.rule(docs: "", detail: Self.realDetail)
        #expect(rule.triggeringExamples == [
            "NSNumber() as! Int",
            "let configuration = Configuration()\nlet value = configuration as! Int"
        ])
        #expect(rule.nonTriggeringExamples == ["NSNumber() as? Int"])
        #expect(rule.name == "Force Cast")
    }

    @Test("examples from the docs are not mixed with the command's, even when the docs have one kind")
    @MainActor
    func docsExamplesTakePrecedence() async throws {
        let docs = """
            # Force Cast

            Force casts should be avoided

            ## Non Triggering Examples

            ```swift
            NSNumber() as? Int
            ```
            """
        let rule = try await Self.rule(docs: docs, detail: Self.realDetail)
        #expect(rule.nonTriggeringExamples == ["NSNumber() as? Int"])
        #expect(rule.triggeringExamples.isEmpty)
    }

    @Test("docs with no title keep the name the rule already had")
    @MainActor
    func untitledDocsKeepTheName() async throws {
        let rule = try await Self.rule(docs: "Force casts should be avoided\n", detail: "no header here")
        #expect(rule.name == "Force Cast")
        #expect(rule.description == "Force casts should be avoided")
    }
}
