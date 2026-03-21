//
//  RuleRegistryCacheTests.swift
//  SwiftLIntRuleStudioTests
//
//  Cache and lookup tests for RuleRegistry
//

import Testing
@testable import SwiftLIntRuleStudio

struct RuleRegistryCacheTests {
    @Test("RuleRegistry initializes with empty rules")
    @MainActor
    func testInitialization() {
        let mockCLI = MockSwiftLintCLIActor()
        let mockCache = MockCacheManager()
        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: mockCache)

        #expect(registry.rules.isEmpty)
        #expect(egistry.isLoading == false)
    }

    @Test("RuleRegistry loads cached rules when SwiftLint fails")
    @MainActor
    func testLoadFromCacheOnFailure() async throws {
        let mockCLI = MockSwiftLintCLIActor(shouldFail: true)
        let mockCache = MockCacheManager()

        let cachedRule = Rule(
            id: "cached_rule",
            name: "Cached Rule",
            description: "A cached rule",
            category: .style,
            isOptIn: false,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil
        )
        mockCache.cachedRules = [cachedRule]

        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: mockCache)
        let rules = try await registry.loadRules()

        let rule = try #require(rules.first, "Expected one cached rule")
        #expect(rule.id == "cached_rule")
    }

    @Test("RuleRegistry throws error when both SwiftLint and cache fail")
    @MainActor
    func testThrowsWhenBothFail() async {
        let mockCLI = MockSwiftLintCLIActor(shouldFail: true)
        let mockCache = MockCacheManager()
        mockCache.shouldFailLoad = true

        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: mockCache)

        await #expect(throws: Error.self) {
            try await registry.loadRules()
        }
    }

    @Test("RuleRegistry can get rule by ID")
    @MainActor
    func testGetRuleById() async throws {
        let mockCLI = MockSwiftLintCLIActor(shouldFail: true)
        let mockCache = MockCacheManager()

        let rule1 = Rule(
            id: "rule1",
            name: "Rule 1",
            description: "First rule",
            category: .style,
            isOptIn: false,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil
        )

        let rule2 = Rule(
            id: "rule2",
            name: "Rule 2",
            description: "Second rule",
            category: .lint,
            isOptIn: true,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil
        )

        mockCache.cachedRules = [rule1, rule2]

        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: mockCache)
        _ = try await registry.loadRules()

        let found = try #require(registry.getRule(id: "rule1"))
        #expect(found.id == "rule1")

        let notFound = registry.getRule(id: "nonexistent")
        #expect(notFound == nil)
    }
}
