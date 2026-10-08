//
//  RuleRegistryTableColumnTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The `swiftlint rules` table's columns past the identifier: a row of
//  box-drawing characters is a border, not a rule, and the analyzer and
//  SourceKit columns are read by position.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct RuleRegistryTableColumnTests {

    private static let registry = RuleRegistry(
        swiftLintCLI: MockSwiftLintCLIActor(mockRulesData: Data()),
        cacheManager: MockCacheManager()
    )

    @Test("a border drawn with box characters between pipes is not a rule")
    func boxDrawingBorder() {
        #expect(Self.registry.parseRuleLine(from: "| ──────── | ───── | ─── | ─── | ──── | ── | ── |") == nil)
    }

    @Test("the analyzer and SourceKit columns are read")
    func analyzerColumn() throws {
        let rule = try #require(Self.registry.parseRuleLine(
            from: "| capture_variable | yes | no | no | lint | yes | yes | |"
        ))
        #expect(rule.isAnalyzer)
        #expect(rule.usesSourceKit)
        let plain = try #require(Self.registry.parseRuleLine(
            from: "| force_cast | no | no | yes | idiomatic | no | no | |"
        ))
        #expect(plain.isAnalyzer == false)
    }
}
