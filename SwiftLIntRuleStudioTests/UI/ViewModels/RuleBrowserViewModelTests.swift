//
//  RuleBrowserViewModelTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for RuleBrowserViewModel filtering and sorting
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

@MainActor
struct RuleBrowserViewModelTests {
    
    private struct StubSwiftLintCLI: SwiftLintCLIProtocol {
        func detectSwiftLintPath() async throws -> URL { throw SwiftLintError.notFound }
        func executeRulesCommand() async throws -> Data { Data() }
        func executeRuleDetailCommand(ruleId: String) async throws -> Data { Data() }
        func generateDocsForRule(ruleId: String) async throws -> String { "" }
        func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data { Data() }
        func getVersion() async throws -> String { "0.0.0" }
    }
    
    private func makeRegistry(with rules: [Rule]) -> RuleRegistry {
        let cache = CacheManager.createForTesting()
        let registry = RuleRegistry(swiftLintCLI: StubSwiftLintCLI(), cacheManager: cache)
        registry.setRulesForTesting(rules)
        return registry
    }
    
    private func makeRule(
        id: String,
        name: String,
        description: String,
        category: RuleCategory,
        isOptIn: Bool,
        isEnabled: Bool
    ) -> Rule {
        Rule(
            id: id,
            name: name,
            description: description,
            category: category,
            isOptIn: isOptIn,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: isEnabled,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: nil
        )
    }
    
    @Test("RuleBrowserViewModel filters by search and status")
    func testSearchAndStatusFilters() {
        let rules = [
            makeRule(id: "force_cast", name: "Force Cast", description: "Avoid force casts", category: .lint, isOptIn: false, isEnabled: true),
            makeRule(id: "trailing_whitespace", name: "Trailing Whitespace", description: "Remove whitespace", category: .style, isOptIn: false, isEnabled: false),
            makeRule(id: "opt_in_rule", name: "Opt In Rule", description: "Loading...", category: .performance, isOptIn: true, isEnabled: false)
        ]
        
        let viewModel = RuleBrowserViewModel(ruleRegistry: makeRegistry(with: rules))
        
        viewModel.searchText = "force"
        #expect(viewModel.filteredRules.map(\.id) == ["force_cast"])
        
        viewModel.searchText = "loading"
        #expect(viewModel.filteredRules.isEmpty == true)
        
        viewModel.searchText = ""
        viewModel.selectedStatus = .enabled
        #expect(viewModel.filteredRules.map(\.id) == ["force_cast"])
        
        viewModel.selectedStatus = .disabled
        #expect(viewModel.filteredRules.map(\.id).sorted() == ["opt_in_rule", "trailing_whitespace"])
        
        viewModel.selectedStatus = .optIn
        #expect(viewModel.filteredRules.map(\.id) == ["opt_in_rule"])
    }
    
    @Test("RuleBrowserViewModel filters by category and sorts")
    func testCategoryAndSorting() {
        let rules = [
            makeRule(id: "b_rule", name: "Beta", description: "B", category: .style, isOptIn: false, isEnabled: true),
            makeRule(id: "a_rule", name: "Alpha", description: "A", category: .lint, isOptIn: false, isEnabled: true),
            makeRule(id: "c_rule", name: "Gamma", description: "C", category: .style, isOptIn: false, isEnabled: true)
        ]
        
        let viewModel = RuleBrowserViewModel(ruleRegistry: makeRegistry(with: rules))
        
        viewModel.selectedCategory = .style
        #expect(viewModel.filteredRules.map(\.id).sorted() == ["b_rule", "c_rule"])
        
        viewModel.selectedCategory = nil
        viewModel.selectedSortOption = .identifier
        #expect(viewModel.filteredRules.map(\.id) == ["a_rule", "b_rule", "c_rule"])
    }
    
    @Test("RuleBrowserViewModel categoryCounts respect filters")
    func testCategoryCounts() {
        let rules = [
            makeRule(id: "a_rule", name: "Alpha Rule", description: "Alpha", category: .lint, isOptIn: false, isEnabled: true),
            makeRule(id: "b_rule", name: "Beta Rule", description: "Beta", category: .style, isOptIn: false, isEnabled: false),
            makeRule(id: "c_rule", name: "Gamma Rule", description: "Gamma", category: .performance, isOptIn: true, isEnabled: true)
        ]
        
        let viewModel = RuleBrowserViewModel(ruleRegistry: makeRegistry(with: rules))
        
        viewModel.searchText = "rule"
        viewModel.selectedStatus = .enabled
        
        let counts = viewModel.categoryCounts
        #expect(counts[.lint] == 1)
        #expect(counts[.performance] == 1)
        #expect(counts[.style] == nil)
    }
    
    @Test("RuleBrowserViewModel clearFilters resets state")
    func testClearFilters() {
        let rules = [
            makeRule(id: "rule", name: "Rule", description: "Rule", category: .lint, isOptIn: false, isEnabled: true)
        ]
        let viewModel = RuleBrowserViewModel(ruleRegistry: makeRegistry(with: rules))
        
        viewModel.searchText = "rule"
        viewModel.selectedCategory = .lint
        viewModel.selectedStatus = .enabled
        
        viewModel.clearFilters()
        #expect(viewModel.searchText.isEmpty == true)
        #expect(viewModel.selectedCategory == nil)
        #expect(viewModel.selectedStatus == .all)
    }
}

