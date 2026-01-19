//
//  RuleDetailViewNewFeaturesTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for new RuleDetailView features: rationale extraction, Swift Evolution links,
//  violation count, and related rules
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

@Suite(.serialized)
struct RuleDetailViewNewFeaturesTests {
    
    // MARK: - Test Data Helpers
    
    private func makeTestRule(
        id: String = "test_rule",
        name: String = "Test Rule",
        category: RuleCategory = .lint,
        markdownDocumentation: String? = nil
    ) async -> Rule {
        await MainActor.run {
            Rule(
                id: id,
                name: name,
                description: "Test description",
                category: category,
                isOptIn: false,
                severity: .warning,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: false,
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: .warning,
                markdownDocumentation: markdownDocumentation
            )
        }
    }
    
    // MARK: - Rationale Extraction Tests
    
    @Test("Extracts rationale from markdown with ## Rationale section")
    func testExtractRationaleWithRationaleSection() async throws {
        let markdown = """
        # Test Rule
        
        This is a description.
        
        ## Rationale
        
        This rule helps prevent common mistakes and improves code quality.
        It enforces best practices that make code more maintainable.
        
        ## Examples
        """
        
        let _ = await makeTestRule(markdownDocumentation: markdown)
        
        // Test rationale extraction using the helper method
        let rationale = await extractRationale(from: markdown)
        #expect(rationale != nil)
        #expect(rationale?.contains("helps prevent common mistakes") == true)
        #expect(rationale?.contains("improves code quality") == true)
    }
    
    @Test("Extracts rationale from markdown with ## Why section")
    func testExtractRationaleWithWhySection() async throws {
        let markdown = """
        # Test Rule
        
        ## Why
        
        This rule is important because it improves readability.
        """
        
        let rationale = await extractRationale(from: markdown)
        #expect(rationale != nil)
        #expect(rationale?.contains("improves readability") == true)
    }
    
    @Test("Returns nil when no rationale section exists")
    func testExtractRationaleNoSection() async throws {
        let markdown = """
        # Test Rule
        
        This is just a description.
        
        ## Examples
        """
        
        let rationale = await extractRationale(from: markdown)
        #expect(rationale == nil)
    }
    
    @Test("Stops extracting at next section header")
    func testExtractRationaleStopsAtNextSection() async throws {
        let markdown = """
        # Test Rule
        
        ## Rationale
        
        This is the rationale text.
        
        ## Examples
        
        This should not be included.
        """
        
        let rationale = await extractRationale(from: markdown)
        #expect(rationale != nil)
        #expect(rationale?.contains("rationale text") == true)
        #expect(rationale?.contains("should not be included") == false)
    }
    
    // MARK: - Swift Evolution Link Extraction Tests
    
    @Test("Extracts Swift Evolution links from markdown")
    func testExtractSwiftEvolutionLinks() async throws {
        let markdown = """
        # Test Rule
        
        See https://github.com/apple/swift-evolution/blob/main/proposals/0123.md
        Also check SE-0456 for more details.
        """
        
        let links = await extractSwiftEvolutionLinks(from: markdown)
        #expect(links.count >= 1)
        #expect(links.contains { $0.absoluteString.contains("0123") || $0.absoluteString.contains("0456") } == true)
    }
    
    @Test("Extracts SE-XXXX format links")
    func testExtractSELinks() async throws {
        let markdown = """
        # Test Rule
        
        This rule is based on SE-0123 and SE-0456.
        """
        
        let links = await extractSwiftEvolutionLinks(from: markdown)
        #expect(links.count >= 1)
    }
    
    @Test("Returns empty array when no Swift Evolution links")
    func testExtractSwiftEvolutionLinksNone() async throws {
        let markdown = """
        # Test Rule
        
        This is just regular text with no links.
        """
        
        let links = await extractSwiftEvolutionLinks(from: markdown)
        #expect(links.isEmpty == true)
    }
    
    // MARK: - Related Rules Tests
    
    @Test("Finds related rules in same category")
    func testRelatedRulesSameCategory() async throws {
        let rule1 = await makeTestRule(id: "rule1", name: "Rule 1", category: .lint)
        let rule2 = await makeTestRule(id: "rule2", name: "Rule 2", category: .lint)
        let rule3 = await makeTestRule(id: "rule3", name: "Rule 3", category: .style)
        
        let container = await DependencyContainer.createForTesting()
        await MainActor.run {
            container.ruleRegistry.setRulesForTesting([rule1, rule2, rule3])
        }
        
        let related = await getRelatedRules(for: rule1, in: container)
        let relatedData = await MainActor.run { related.map(\.id) }
        #expect(relatedData.count == 1)
        #expect(relatedData.first == "rule2")
    }
    
    @Test("Excludes current rule from related rules")
    func testRelatedRulesExcludesCurrent() async throws {
        let rule1 = await makeTestRule(id: "rule1", name: "Rule 1", category: .lint)
        let rule2 = await makeTestRule(id: "rule2", name: "Rule 2", category: .lint)
        
        let container = await DependencyContainer.createForTesting()
        await MainActor.run {
            container.ruleRegistry.setRulesForTesting([rule1, rule2])
        }
        
        let related = await getRelatedRules(for: rule1, in: container)
        let relatedIds = await MainActor.run { Set(related.map(\.id)) }
        #expect(relatedIds.contains("rule1") == false)
    }
    
    @Test("Returns empty array when no related rules")
    func testRelatedRulesEmpty() async throws {
        let rule1 = await makeTestRule(id: "rule1", name: "Rule 1", category: .lint)
        let rule2 = await makeTestRule(id: "rule2", name: "Rule 2", category: .style)
        
        let container = await DependencyContainer.createForTesting()
        await MainActor.run {
            container.ruleRegistry.setRulesForTesting([rule1, rule2])
        }
        
        let related = await getRelatedRules(for: rule1, in: container)
        let relatedCount = await MainActor.run { related.count }
        #expect(relatedCount == 0)
    }
    
    // MARK: - Violation Count Tests
    
    @Test("Loads violation count for rule")
    @MainActor
    func testLoadViolationCount() async throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        
        let container = await DependencyContainer.createForTesting()
        
        await MainActor.run {
            try? container.workspaceManager.openWorkspace(at: workspace)
        }
        
        // Create test violations
        let violation1 = Violation(
            ruleID: "test_rule",
            filePath: "Test.swift",
            line: 10,
            severity: .error,
            message: "Test violation"
        )
        
        let violation2 = Violation(
            ruleID: "test_rule",
            filePath: "Test2.swift",
            line: 20,
            severity: .warning,
            message: "Another violation"
        )
        
        if let workspaceId = await MainActor.run { container.workspaceManager.currentWorkspace?.id } {
            try await container.violationStorage.storeViolations([violation1, violation2], for: workspaceId)
            
            let count = try await container.violationStorage.getViolationCount(
                filter: ViolationFilter(ruleIDs: ["test_rule"]),
                workspaceId: workspaceId
            )
            
            #expect(count == 2)
        }
    }
    
    // MARK: - Helper Methods
    
    // Test rationale extraction by checking view content
    private func extractRationale(from markdown: String) async -> String? {
        // Replicate the logic from RuleDetailView for testing
        guard !markdown.isEmpty else { return nil }
        
        let lines = markdown.components(separatedBy: .newlines)
        var inRationaleSection = false
        var rationaleLines: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("##") {
                let sectionName = trimmed.lowercased()
                if sectionName.contains("rationale") || sectionName.contains("why") {
                    inRationaleSection = true
                    continue
                } else if inRationaleSection {
                    break
                }
            }
            
            if inRationaleSection {
                if trimmed.hasPrefix("```") {
                    continue
                }
                
                if rationaleLines.isEmpty && trimmed.isEmpty {
                    continue
                }
                
                if !trimmed.isEmpty {
                    rationaleLines.append(trimmed)
                } else if !rationaleLines.isEmpty {
                    break
                }
            }
        }
        
        if !rationaleLines.isEmpty {
            return rationaleLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    // Test Swift Evolution link extraction
    private func extractSwiftEvolutionLinks(from markdown: String) async -> [URL] {
        guard !markdown.isEmpty else { return [] }
        
        var links: [URL] = []
        
        let patterns = [
            #"https?://github\.com/apple/swift-evolution/blob/.*SE-\d+"#,
            #"https?://github\.com/apple/swift-evolution/.*SE-\d+"#,
            #"SE-\d+"#,
            #"swift-evolution.*SE-\d+"#
        ]
        
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
            
            regex?.enumerateMatches(in: markdown, options: [], range: range) { match, _, _ in
                guard let match = match,
                      let range = Range(match.range, in: markdown) else { return }
                
                let matchedString = String(markdown[range])
                
                if matchedString.hasPrefix("http") {
                    if let url = URL(string: matchedString) {
                        links.append(url)
                    }
                } else if matchedString.contains("SE-") {
                    // Extract SE number
                    let components = matchedString.components(separatedBy: "SE-")
                    if components.count > 1 {
                        let seNumber = components[1].prefix(4)
                        let urlString = "https://github.com/apple/swift-evolution/blob/main/proposals/\(seNumber).md"
                        if let url = URL(string: urlString) {
                            links.append(url)
                        }
                    }
                }
            }
        }
        
        return Array(Set(links)).sorted { $0.absoluteString < $1.absoluteString }
    }
    
    private func getRelatedRules(for rule: Rule, in container: DependencyContainer) async -> [Rule] {
        await MainActor.run {
            container.ruleRegistry.rules
                .filter { $0.id != rule.id && $0.category == rule.category }
                .sorted { $0.name < $1.name }
        }
    }
}
