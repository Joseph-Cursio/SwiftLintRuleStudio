//
//  RuleRegistryDetailsTests.swift
//  SwiftLintRuleStudioTests
//
//  Rule details parsing tests
//

@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

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
        let cli = RuleDetailsSwiftLintCLIActor(docs: "", detail: detail)
        let rule = try await RuleRegistry.fetchRuleDetailsHelper(
            identifier: "example_rule",
            category: .style,
            isOptIn: false,
            swiftLintCLI: cli
        )

        #expect(rule.name == "Example Rule")
        #expect(rule.description.contains("Example description"))
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
        let cli = RuleDetailsSwiftLintCLIActor(docs: docs, detail: detail)
        let rule = try await RuleRegistry.fetchRuleDetailsHelper(
            identifier: "example_rule",
            category: .style,
            isOptIn: false,
            swiftLintCLI: cli
        )

        #expect(rule.name == "Example Rule")
        #expect(rule.description.contains("Example rule description."))
        #expect(rule.triggeringExamples.count == 1)
        #expect(rule.nonTriggeringExamples.count == 1)
    }

    // Regression: previously the details-enrichment pass dropped the analyzer
    // flag because RuleDetailsState.asRule didn't forward it. That meant the UI
    // routed enabled analyzer rules into `opt_in_rules` instead of
    // `analyzer_rules`, and SwiftLint emitted "should be listed in the
    // 'analyzer_rules' configuration section" warnings.
    @Test("fetchRuleDetailsHelper preserves isAnalyzer flag")
    @MainActor
    func testFetchRuleDetailsPreservesAnalyzerFlag() async throws {
        let detail = """
        Capture Variable (capture_variable): Captures a variable
        """
        let cli = RuleDetailsSwiftLintCLIActor(docs: "", detail: detail)
        let rule = try await RuleRegistry.fetchRuleDetailsHelper(
            identifier: "capture_variable",
            category: .lint,
            isOptIn: true,
            swiftLintCLI: cli,
            isAnalyzer: true
        )

        #expect(rule.isAnalyzer == true)
        #expect(rule.isOptIn == true)
    }
}
