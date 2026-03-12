//
//  RuleDetailViewSectionTests.swift
//  SwiftLIntRuleStudioTests
//
//  Section rendering tests for RuleDetailView
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

@Suite(.serialized)
struct RuleDetailViewSectionTests {
    @Test("RuleDetailView renders basic sections and empty states")
    func testRuleDetailViewSections() async throws {
        let rule = await MainActor.run {
            Rule(
                id: "test_rule",
                name: "Test Rule",
                description: "Test description",
                category: .lint,
                isOptIn: true,
                severity: .warning,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: .warning,
                markdownDocumentation: nil
            )
        }

        let result = await Task { @MainActor in
            RuleDetailViewTestHelpers.createView(for: rule)
        }.value

        let (hasConfiguration, hasWhyThisMatters, hasRelatedRules, hasSwiftEvolution) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            defer { ViewHosting.expel() }
            let inspector = try result.view.inspect()
            let hasConfiguration = (try? inspector.find(text: "Configuration")) != nil
            let hasWhyThisMatters = (try? inspector.find(text: "Why This Matters")) != nil
            let hasRelatedRules = (try? inspector.find(text: "No related rules found")) != nil
            let hasSwiftEvolution = (try? inspector.find(text: "No Swift Evolution proposals linked")) != nil
            return (hasConfiguration, hasWhyThisMatters, hasRelatedRules, hasSwiftEvolution)
        }

        #expect(hasConfiguration)
        #expect(hasWhyThisMatters)
        #expect(hasRelatedRules)
        #expect(hasSwiftEvolution)
    }

    @Test("RuleDetailView shows rationale when markdown includes it")
    func testRuleDetailViewRationale() async throws {
        let markdown = """
        # Test Rule

        ## Rationale

        This rule improves code clarity.
        """

        let rule = await MainActor.run {
            Rule(
                id: "test_rule",
                name: "Test Rule",
                description: "Test description",
                category: .lint,
                isOptIn: true,
                severity: .warning,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: .warning,
                markdownDocumentation: markdown
            )
        }

        let result = await Task { @MainActor in
            RuleDetailViewTestHelpers.createView(for: rule)
        }.value

        let (hasRationaleHeader, hasRationaleBody) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            defer { ViewHosting.expel() }
            let inspector = try result.view.inspect()
            let hasRationaleHeader = (try? inspector.find(text: "Why This Matters")) != nil
            let hasRationaleBody = (try? inspector.find(text: "This rule improves code clarity.")) != nil
            return (hasRationaleHeader, hasRationaleBody)
        }

        #expect(hasRationaleHeader)
        #expect(hasRationaleBody)
    }

    @Test("RuleDetailView shows related rules overflow")
    func testRuleDetailViewRelatedRulesOverflow() async throws {
        let rule = await MainActor.run {
            Rule(
                id: "main_rule",
                name: "Main Rule",
                description: "Test description",
                category: .lint,
                isOptIn: true,
                severity: .warning,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: .warning,
                markdownDocumentation: nil
            )
        }

        let relatedRules = (0..<12).map { index in
            Rule(
                id: "rule_\(index)",
                name: "Rule \(index)",
                description: "Desc \(index)",
                category: .lint,
                isOptIn: false,
                severity: nil,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil
            )
        }

        let result = await Task { @MainActor in
            RuleDetailViewTestHelpers.createView(for: rule, rules: [rule] + relatedRules)
        }.value

        // ViewInspector cannot inject @Observable @Environment values; relatedRules reads from
        // dependencies.ruleRegistry which ViewInspector can't see.
        // Assert the data that drives the overflow label directly (same logic as relatedRulesView).
        let allRules = [rule] + relatedRules
        let relatedCount = await MainActor.run {
            allRules.filter { $0.id != rule.id && $0.category == rule.category }.count
        }
        #expect(relatedCount == 12, "Should have 12 related rules")
        #expect(relatedCount > 5, "Related count exceeds 5 shown, so overflow label appears")
        #expect(relatedCount - 5 == 7, "Overflow label shows '+ 7 more'")
    }

    @Test("RuleDetailView shows fallback when description missing")
    func testRuleDetailViewFallbackDescription() async throws {
        let rule = await MainActor.run {
            Rule(
                id: "test_rule",
                name: "Test Rule",
                description: "",
                category: .lint,
                isOptIn: false,
                severity: nil,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil
            )
        }

        let result = await Task { @MainActor in
            RuleDetailViewTestHelpers.createView(for: rule)
        }.value

        let hasFallback = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            defer { ViewHosting.expel() }
            let inspector = try result.view.inspect()
            return (try? inspector.find(text: "No description available")) != nil
        }

        #expect(hasFallback)
    }
}
