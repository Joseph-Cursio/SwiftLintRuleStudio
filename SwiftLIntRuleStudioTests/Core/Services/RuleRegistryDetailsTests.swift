//
//  RuleRegistryDetailsTests.swift
//  SwiftLIntRuleStudioTests
//
//  Rule details parsing tests
//

import Testing
@testable import SwiftLIntRuleStudio

struct RuleRegistryDetailsTests {
    @Test("RuleRegistry parses examples from rule details")
    @MainActor
    func testFetchRuleDetailsFromRuleDetails() async throws {
        let detail = """
        Example Rule (example_rule): Example description

        Triggering Examples (violations are marked with '↓'):
            let value = NSNumber() ↓as! Int

        Non-Triggering Examples:
            if let value = NSNumber() as? Int { }

        Configuration:
        """
        let cli = RuleDetailsSwiftLintCLI(docs: "", detail: detail)
        let rule = try await RuleRegistry.fetchRuleDetailsHelper(
            identifier: "example_rule",
            category: .style,
            isOptIn: false,
            swiftLintCLI: cli
        )

        #expect(rule.name == "Example Rule")
        #expect(rule.description.contains("Example description") == true)
        #expect(rule.triggeringExamples.count == 1)
        #expect(rule.nonTriggeringExamples.count == 1)
        #expect(rule.triggeringExamples.first?.contains("↓") == false)
    }

    @Test("RuleRegistry uses docs examples when available")
    @MainActor
    func testFetchRuleDetailsFromDocs() async throws {
        let docs = """
        # Example Rule

        Example rule description.

        ## Non Triggering Examples

        ```swift
        // Good example
        ```

        ## Triggering Examples

        ```swift
        // Bad example
        ```
        """
        let detail = "Example Rule (example_rule): Example description"
        let cli = RuleDetailsSwiftLintCLI(docs: docs, detail: detail)
        let rule = try await RuleRegistry.fetchRuleDetailsHelper(
            identifier: "example_rule",
            category: .style,
            isOptIn: false,
            swiftLintCLI: cli
        )

        #expect(rule.name == "Example Rule")
        #expect(rule.description.contains("Example rule description.") == true)
        #expect(rule.triggeringExamples.count == 1)
        #expect(rule.nonTriggeringExamples.count == 1)
    }
}
