//
//  RuleDetailViewLinksTests.swift
//  SwiftLIntRuleStudioTests
//
//  Swift Evolution link tests for RuleDetailView
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

@Suite(.serialized)
struct RuleDetailViewLinksTests {
    @Test("RuleDetailView shows Swift Evolution links")
    func testSwiftEvolutionLinks() async throws {
        let rule = await MainActor.run {
            Rule(
                id: "test_rule",
                name: "Test Rule",
                description: "Test description",
                category: .lint,
                isOptIn: false,
                severity: nil,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: .warning,
                markdownDocumentation: "See SE-0001 for details."
            )
        }

        let result = await Task { @MainActor in
            RuleDetailViewTestHelpers.createView(for: rule)
        }.value

        let hasLink = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            defer { ViewHosting.expel() }
            let inspector = try result.view.inspect()
            return (try? inspector.find(text: "https://github.com/apple/swift-evolution/blob/main/proposals/0001.md")) != nil
        }

        #expect(hasLink == true)
    }
}
