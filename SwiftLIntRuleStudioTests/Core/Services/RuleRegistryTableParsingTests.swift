//
//  RuleRegistryTableParsingTests.swift
//  SwiftLIntRuleStudioTests
//
//  Table parsing tests for RuleRegistry
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct RuleRegistryTableParsingTests {
    @Test("RuleRegistry parses table format with all fields")
    @MainActor
    func testParseTableFormatWithAllFields() async throws {
        let tableData = makeRulesTableData(rows: [
            "| force_cast | no | no | yes | lint | no | no | |"
        ])

        let mockCLI = MockSwiftLintCLI(mockRulesData: tableData)
        let mockCache = MockCacheManager()
        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: mockCache)

        let rules = try await registry.loadRules()

        #expect(rules.count == 1)
        let rule = rules[0]
        #expect(rule.id == "force_cast")
        #expect(rule.category == .lint)
        #expect(rule.isOptIn == false)
    }

    @Test("RuleRegistry parses table format with minimal fields")
    @MainActor
    func testParseTableFormatWithMinimalFields() async throws {
        let tableData = makeRulesTableData(rows: [
            "| simple_rule | no | no | yes | style | no | no | |"
        ])

        let mockCLI = MockSwiftLintCLI(mockRulesData: tableData)
        let mockCache = MockCacheManager()
        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: mockCache)

        let rules = try await registry.loadRules()

        #expect(rules.count == 1)
        let rule = rules[0]
        #expect(rule.id == "simple_rule")
        #expect(rule.category == .style)
        #expect(rule.isOptIn == false)
    }

    @Test("RuleRegistry maps all category types correctly")
    @MainActor
    func testCategoryMapping() async throws {
        let tableData = makeRulesTableData(rows: [
            "| style_rule | no | no | yes | style | no | no | |",
            "| lint_rule | no | no | yes | lint | no | no | |",
            "| metrics_rule | no | no | yes | metrics | no | no | |",
            "| performance_rule | no | no | yes | performance | no | no | |",
            "| idiomatic_rule | no | no | yes | idiomatic | no | no | |",
            "| unknown_rule | no | no | yes | unknown_category | no | no | |"
        ])

        let mockCLI = MockSwiftLintCLI(mockRulesData: tableData)
        let mockCache = MockCacheManager()
        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: mockCache)

        let rules = try await registry.loadRules()

        #expect(rules.count == 6)
        #expect(rules[0].category == .style)
        #expect(rules[1].category == .lint)
        #expect(rules[2].category == .metrics)
        #expect(rules[3].category == .performance)
        #expect(rules[4].category == .idiomatic)
        #expect(rules[5].category == .style)
    }

    @Test("RuleRegistry handles case-insensitive category names")
    @MainActor
    func testCaseInsensitiveCategoryMapping() async throws {
        let tableData = makeRulesTableData(rows: [
            "| uppercase_rule | no | no | yes | STYLE | no | no | |",
            "| mixed_case_rule | no | no | yes | LiNt | no | no | |"
        ])

        let mockCLI = MockSwiftLintCLI(mockRulesData: tableData)
        let mockCache = MockCacheManager()
        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: mockCache)

        let rules = try await registry.loadRules()

        #expect(rules.count == 2)
        #expect(rules[0].category == .style)
        #expect(rules[1].category == .lint)
    }

    @Test("RuleRegistry parses opt-in rules correctly")
    @MainActor
    func testOptInRuleParsing() async throws {
        let tableData = makeRulesTableData(rows: [
            "| opt_in_rule | yes | no | no | style | no | no | |",
            "| default_rule | no | no | yes | style | no | no | |",
            "| missing_opt_in | no | no | yes | style | no | no | |"
        ])

        let mockCLI = MockSwiftLintCLI(mockRulesData: tableData)
        let mockCache = MockCacheManager()
        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: mockCache)

        let rules = try await registry.loadRules()

        #expect(rules.count == 3)
        #expect(rules[0].isOptIn == true)
        #expect(rules[1].isOptIn == false)
        #expect(rules[2].isOptIn == false)
    }

    @Test("RuleRegistry parses multiple rules")
    @MainActor
    func testParseMultipleRules() async throws {
        let tableData = makeRulesTableData(rows: [
            "| rule1 | no | no | yes | style | no | no | |",
            "| rule2 | no | no | yes | lint | no | no | |",
            "| rule3 | no | no | yes | metrics | no | no | |"
        ])

        let mockCLI = MockSwiftLintCLI(mockRulesData: tableData)
        let mockCache = MockCacheManager()
        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: mockCache)

        let rules = try await registry.loadRules()

        #expect(rules.count == 3)
        #expect(rules[0].id == "rule1")
        #expect(rules[1].id == "rule2")
        #expect(rules[2].id == "rule3")
    }

    @Test("RuleRegistry handles empty table")
    @MainActor
    func testParseEmptyTable() async {
        let emptyTable = makeRulesTableData(rows: [])

        let mockCLI = MockSwiftLintCLI(mockRulesData: emptyTable)
        let mockCache = MockCacheManager()
        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: mockCache)

        await #expect(throws: Error.self) {
            try await registry.loadRules()
        }
    }

    @Test("RuleRegistry throws error on invalid table format")
    @MainActor
    func testParseInvalidTable() async {
        let invalidData = Data("not valid table format".utf8)

        let mockCLI = MockSwiftLintCLI(mockRulesData: invalidData)
        let mockCache = MockCacheManager()
        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: mockCache)

        await #expect(throws: Error.self) {
            try await registry.loadRules()
        }
    }
}
