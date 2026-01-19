//
//  RuleRegistryTests.swift
//  SwiftLintRuleStudioTests
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// Mock implementations for testing
actor MockSwiftLintCLI: SwiftLintCLIProtocol {
    private let shouldFail: Bool
    private let mockRulesData: Data?
    private var mockLintOutput: Data = Data()
    private var shouldHang: Bool = false
    var lintCommandHandler: (@Sendable (URL?, URL) async throws -> Data)?
    
    init(shouldFail: Bool = false, mockRulesData: Data? = nil) {
        self.shouldFail = shouldFail
        self.mockRulesData = mockRulesData
    }
    
    func setMockLintOutput(_ data: Data) {
        mockLintOutput = data
    }
    
    func setShouldHang(_ value: Bool) {
        shouldHang = value
    }
    
    func setLintCommandHandler(_ handler: @escaping @Sendable (URL?, URL) async throws -> Data) {
        lintCommandHandler = handler
    }
    
    func detectSwiftLintPath() throws -> URL {
        if shouldFail {
            throw SwiftLintError.notFound
        }
        // Use a more portable path - check common locations
        let possiblePaths = [
            "/opt/homebrew/bin/swiftlint",
            "/usr/local/bin/swiftlint",
            "/usr/bin/swiftlint"
        ]
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        // Fallback to /usr/local/bin/swiftlint for mock purposes
        return URL(fileURLWithPath: "/usr/local/bin/swiftlint")
    }
    
    func executeRulesCommand() throws -> Data {
        if shouldFail {
            throw SwiftLintError.executionFailed(message: "Mock failure")
        }
        
        // If mockRulesData is provided, use it (for table format tests)
        if let data = mockRulesData {
            return data
        }
        
        // Default: return empty table format
        return """
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        | identifier | opt-in | correctable | enabled in your config | kind | analyzer | uses sourcekit | configuration |
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        """.data(using: .utf8) ?? Data()
    }
    
    func executeRuleDetailCommand(ruleId: String) throws -> Data {
        if shouldFail {
            throw SwiftLintError.executionFailed(message: "Mock failure")
        }
        // Return mock rule detail
        let mockDetail = """
        Force Cast (force_cast): Force casts should be avoided
        
        Configuration (YAML):
        
          force_cast:
            severity: error
        
        Triggering Examples (violations are marked with '↓'):
        
        Example #1
        
            NSNumber() ↓as! Int
        
        Non-Triggering Examples:
        
        Example #1
        
            if let number = value as? Int { }
        """
        return mockDetail.data(using: .utf8) ?? Data()
    }
    
    func generateDocsForRule(ruleId: String) throws -> String {
        if shouldFail {
            throw SwiftLintError.executionFailed(message: "Mock failure")
        }
        // Return mock markdown documentation
        return """
        # \(ruleId.capitalized)
        
        This is a test rule for \(ruleId).
        
        * **Identifier:** `\(ruleId)`
        * **Enabled by default:** Yes
        * **Supports autocorrection:** No
        
        ## Non Triggering Examples
        
        ```swift
        // Good code
        ```
        
        ## Triggering Examples
        
        ```swift
        // Bad code
        ```
        """
    }
    
    func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data {
        if shouldHang {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        
        if shouldFail {
            throw SwiftLintError.executionFailed(message: "Mock failure")
        }
        
        // Use handler if provided, otherwise use mockLintOutput
        if let handler = lintCommandHandler {
            return try await handler(configPath, workspacePath)
        }
        
        return mockLintOutput
    }
    
    func getVersion() throws -> String {
        if shouldFail {
            throw SwiftLintError.invalidVersion
        }
        return "0.50.0"
    }
}

final class MockCacheManager: CacheManagerProtocol, @unchecked Sendable {
    var cachedRules: [Rule] = []
    var shouldFailLoad = false
    var shouldFailSave = false
    var cachedVersion: String?
    var cachedDocsDirectory: URL?
    
    func loadCachedRules() throws -> [Rule] {
        if shouldFailLoad {
            throw NSError(domain: "TestError", code: 1)
        }
        return cachedRules
    }
    
    func saveCachedRules(_ rules: [Rule]) throws {
        if shouldFailSave {
            throw NSError(domain: "TestError", code: 1)
        }
        cachedRules = rules
    }
    
    func clearCache() throws {
        cachedRules = []
    }
    
    func getCachedSwiftLintVersion() throws -> String? {
        return cachedVersion
    }
    
    func saveSwiftLintVersion(_ version: String) throws {
        cachedVersion = version
    }
    
    func getCachedDocsDirectory() -> URL? {
        return cachedDocsDirectory
    }
    
    func saveDocsDirectory(_ url: URL) throws {
        cachedDocsDirectory = url
    }
    
    func clearDocsCache() throws {
        cachedDocsDirectory = nil
    }
}

struct RuleRegistryTests {
    
    @Test("RuleRegistry initializes with empty rules")
    @MainActor
    func testInitialization() {
        let mockCLI = MockSwiftLintCLI()
        let mockCache = MockCacheManager()
        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: mockCache)
        
        #expect(registry.rules.isEmpty)
        #expect(registry.isLoading == false)
    }
    
    @Test("RuleRegistry loads cached rules when SwiftLint fails")
    @MainActor
    func testLoadFromCacheOnFailure() async throws {
        let mockCLI = MockSwiftLintCLI(shouldFail: true)
        let mockCache = MockCacheManager()
        
        // Pre-populate cache
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
        
        // Should load from cache even if SwiftLint fails
        let rules = try await registry.loadRules()
        
        #expect(rules.count == 1)
        #expect(rules[0].id == "cached_rule")
    }
    
    @Test("RuleRegistry throws error when both SwiftLint and cache fail")
    @MainActor
    func testThrowsWhenBothFail() async {
        let mockCLI = MockSwiftLintCLI(shouldFail: true)
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
        // Make SwiftLint fail so it uses cached rules
        let mockCLI = MockSwiftLintCLI(shouldFail: true)
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
        
        // Load rules from cache (SwiftLint will fail, so it uses cache)
        _ = try await registry.loadRules()
        
        let found = registry.getRule(id: "rule1")
        #expect(found?.id == "rule1")
        
        let notFound = registry.getRule(id: "nonexistent")
        #expect(notFound == nil)
    }
    
    // MARK: - JSON Parsing Tests
    
    @Test("RuleRegistry parses table format with all fields")
    @MainActor
    func testParseTableFormatWithAllFields() async throws {
        let tableData = """
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        | identifier | opt-in | correctable | enabled in your config | kind | analyzer | uses sourcekit | configuration |
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        | force_cast | no | no | yes | lint | no | no | |
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        """.data(using: .utf8)!
        
        let mockCLI = MockSwiftLintCLI(mockRulesData: tableData)
        let mockCache = MockCacheManager()
        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: mockCache)
        
        let rules = try await registry.loadRules()
        
        #expect(rules.count == 1)
        let rule = rules[0]
        #expect(rule.id == "force_cast")
        #expect(rule.category == .lint)
        #expect(rule.isOptIn == false)
        // Note: Name and description come from generate-docs or rules detail command, not table
    }
    
    @Test("RuleRegistry parses table format with minimal fields")
    @MainActor
    func testParseTableFormatWithMinimalFields() async throws {
        let tableData = """
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        | identifier | opt-in | correctable | enabled in your config | kind | analyzer | uses sourcekit | configuration |
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        | simple_rule | no | no | yes | style | no | no | |
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        """.data(using: .utf8)!
        
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
        let tableData = """
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        | identifier | opt-in | correctable | enabled in your config | kind | analyzer | uses sourcekit | configuration |
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        | style_rule | no | no | yes | style | no | no | |
        | lint_rule | no | no | yes | lint | no | no | |
        | metrics_rule | no | no | yes | metrics | no | no | |
        | performance_rule | no | no | yes | performance | no | no | |
        | idiomatic_rule | no | no | yes | idiomatic | no | no | |
        | unknown_rule | no | no | yes | unknown_category | no | no | |
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        """.data(using: .utf8)!
        
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
        #expect(rules[5].category == .style) // Unknown defaults to style
    }
    
    @Test("RuleRegistry handles case-insensitive category names")
    @MainActor
    func testCaseInsensitiveCategoryMapping() async throws {
        let tableData = """
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        | identifier | opt-in | correctable | enabled in your config | kind | analyzer | uses sourcekit | configuration |
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        | uppercase_rule | no | no | yes | STYLE | no | no | |
        | mixed_case_rule | no | no | yes | LiNt | no | no | |
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        """.data(using: .utf8)!
        
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
        let tableData = """
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        | identifier | opt-in | correctable | enabled in your config | kind | analyzer | uses sourcekit | configuration |
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        | opt_in_rule | yes | no | no | style | no | no | |
        | default_rule | no | no | yes | style | no | no | |
        | missing_opt_in | no | no | yes | style | no | no | |
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        """.data(using: .utf8)!
        
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
        let tableData = """
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        | identifier | opt-in | correctable | enabled in your config | kind | analyzer | uses sourcekit | configuration |
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        | rule1 | no | no | yes | style | no | no | |
        | rule2 | no | no | yes | lint | no | no | |
        | rule3 | no | no | yes | metrics | no | no | |
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        """.data(using: .utf8)!
        
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
        let emptyTable = """
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        | identifier | opt-in | correctable | enabled in your config | kind | analyzer | uses sourcekit | configuration |
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        +------------------------------------------+--------+-------------+------------------------+-------------+----------+----------------+---------------+
        """.data(using: .utf8)!
        
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
        let invalidData = "not valid table format".data(using: .utf8)!
        
        let mockCLI = MockSwiftLintCLI(mockRulesData: invalidData)
        let mockCache = MockCacheManager()
        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: mockCache)
        
        await #expect(throws: Error.self) {
            try await registry.loadRules()
        }
    }
}

