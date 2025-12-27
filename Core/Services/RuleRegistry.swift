//
//  RuleRegistry.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import Combine

/// Service for managing SwiftLint rules metadata
@MainActor
protocol RuleRegistryProtocol {
    func loadRules() async throws -> [Rule]
    func getRule(id: String) -> Rule?
    func refreshRules() async throws
    var rules: [Rule] { get }
}

@MainActor
class RuleRegistry: RuleRegistryProtocol, ObservableObject {
    @Published private(set) var rules: [Rule] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?
    
    private let swiftLintCLI: SwiftLintCLIProtocol
    private let cacheManager: CacheManagerProtocol
    
    init(swiftLintCLI: SwiftLintCLIProtocol, cacheManager: CacheManagerProtocol) {
        self.swiftLintCLI = swiftLintCLI
        self.cacheManager = cacheManager
    }
    
    func loadRules() async throws -> [Rule] {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Try to load from cache first
            if let cachedRules = try? cacheManager.loadCachedRules() {
                self.rules = cachedRules
            }
            
            // Always try to refresh from SwiftLint
            let freshRules = try await fetchRulesFromSwiftLint()
            self.rules = freshRules
            try? cacheManager.saveCachedRules(freshRules)
            return freshRules
        } catch {
            self.error = error
            // Return cached rules if available, even if refresh failed
            if rules.isEmpty {
                throw error
            }
            return rules
        }
    }
    
    func getRule(id: String) -> Rule? {
        rules.first { $0.id == id }
    }
    
    /// Fetch details for a specific rule on demand (useful when rule was loaded without details)
    func fetchRuleDetailsIfNeeded(id: String) async {
        guard let rule = getRule(id: id),
              rule.markdownDocumentation == nil || rule.markdownDocumentation?.isEmpty == true else {
            // Rule already has documentation
            return
        }
        
        do {
            let detailedRule = try await fetchRuleDetails(identifier: rule.id, category: rule.category, isOptIn: rule.isOptIn)
            
            // Update the rule in the rules array
            if let index = rules.firstIndex(where: { $0.id == id }) {
                rules[index] = detailedRule
                objectWillChange.send()
            }
        } catch {
            print("⚠️ Failed to fetch details for rule \(id): \(error.localizedDescription)")
        }
    }
    
    func refreshRules() async throws {
        _ = try await loadRules()
    }
    
    private func fetchRulesFromSwiftLint() async throws -> [Rule] {
        let output = try await swiftLintCLI.executeRulesCommand()
        return try await parseRules(from: output)
    }
    
    private func parseRules(from data: Data) async throws -> [Rule] {
        // Parse the table output from `swiftlint rules`
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "RuleRegistry", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode SwiftLint output"])
        }
        
        // Debug: Print the actual output to see what we're getting
        print("SwiftLint output (first 500 chars):\n\(String(text.prefix(500)))")
        
        let lines = text.components(separatedBy: .newlines)
        var rules: [Rule] = []
        
        // Find data rows (lines that start with "|" and contain rule data)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines, borders (lines with only +, -, or |), and header rows
            if trimmed.isEmpty || 
               trimmed.hasPrefix("+") || 
               !trimmed.hasPrefix("|") ||
               trimmed.lowercased().contains("identifier") {  // Skip header row
                continue
            }
            
            // Split by | and filter out empty strings
            let columns = trimmed.split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            guard columns.count >= 5 else { 
                print("Skipping line (not enough columns: \(columns.count)): \(String(trimmed.prefix(80)))")
                continue 
            }
            
            // First column should be identifier
            let identifier = columns[0]
            guard !identifier.isEmpty && !identifier.contains("─") else { 
                continue 
            }
            
            // Parse opt-in status (column 1)
            let optInStr = columns.count > 1 ? columns[1].lowercased() : "no"
            let isOptIn = optInStr == "yes"
            
            // Category is typically in column 4 (index 4, which is the 5th column)
            let kindStr = columns.count > 4 ? columns[4].lowercased() : "style"
            let category = mapCategory(kindStr)
            
            // Create basic rule first (we'll fetch details on demand or in background)
            // In SwiftLint, non-opt-in rules are enabled by default
            let rule = Rule(
                id: identifier,
                name: identifier.replacingOccurrences(of: "_", with: " ").capitalized,
                description: "Loading...", // Will be updated when details are fetched
                category: category,
                isOptIn: isOptIn,
                severity: nil,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil,
                isEnabled: !isOptIn, // Enabled by default unless it's an opt-in rule
                supportsAutocorrection: false,
                minimumSwiftVersion: nil,
                defaultSeverity: nil,
                markdownDocumentation: nil
            )
            rules.append(rule)
        }
        
        print("Parsed \(rules.count) rules from SwiftLint output")
        
        guard !rules.isEmpty else {
            throw NSError(domain: "RuleRegistry", code: 2, userInfo: [NSLocalizedDescriptionKey: "No rules found in SwiftLint output. Make sure SwiftLint is installed and accessible."])
        }
        
        // Fetch details for rules in batches (to avoid overwhelming SwiftLint)
        // For now, fetch details for first 20 rules immediately, rest can be lazy-loaded
        // In test environments, we may skip detail fetching to speed up tests
        let rulesToFetchDetails = Array(rules.prefix(20))
        var updatedRules = rules
        
        // Fetch details in parallel for first batch
        // If detail fetching fails, we still return the basic rules
        await withTaskGroup(of: (Int, Rule).self) { group in
            for (index, rule) in rulesToFetchDetails.enumerated() {
                group.addTask { [weak self] in
                    guard let self = self else {
                        return (index, rule)
                    }
                    do {
                        let detailedRule = try await self.fetchRuleDetails(identifier: rule.id, category: rule.category, isOptIn: rule.isOptIn)
                        return (index, detailedRule)
                    } catch {
                        // Return original rule if detail fetch fails - this is expected in some test scenarios
                        print("Failed to fetch details for rule \(rule.id): \(error.localizedDescription)")
                        return (index, rule)
                    }
                }
            }
            
            for await (index, detailedRule) in group {
                updatedRules[index] = detailedRule
            }
        }
        
        return updatedRules
    }
    
    private func mapCategory(_ kind: String) -> RuleCategory {
        switch kind {
        case "style":
            return .style
        case "lint":
            return .lint
        case "metrics":
            return .metrics
        case "performance":
            return .performance
        case "idiomatic":
            return .idiomatic
        default:
            return .style
        }
    }
    
    private func fetchRuleDetails(identifier: String, category: RuleCategory, isOptIn: Bool) async throws -> Rule {
        // Try to fetch from generate-docs first (better structured data)
        var parsedDoc: ParsedRuleDocumentation?
        var name = identifier.replacingOccurrences(of: "_", with: " ").capitalized
        var description = "No description available"
        var triggeringExamples: [String] = []
        var nonTriggeringExamples: [String] = []
        var supportsAutocorrection = false
        var minimumSwiftVersion: String?
        var defaultSeverity: Severity?
        var markdownDoc: String?
        
        // Try generate-docs first
        do {
            let markdown = try await swiftLintCLI.generateDocsForRule(ruleId: identifier)
            markdownDoc = markdown
            
            // Only parse if we got markdown content
            if !markdown.isEmpty {
                parsedDoc = RuleDocumentationParser.parse(markdown: markdown)
                
                if let doc = parsedDoc {
                    if !doc.name.isEmpty {
                        name = doc.name
                    }
                    if !doc.description.isEmpty {
                        description = doc.description
                    }
                    triggeringExamples = doc.triggeringExamples
                    nonTriggeringExamples = doc.nonTriggeringExamples
                    supportsAutocorrection = doc.supportsAutocorrection
                    minimumSwiftVersion = doc.minimumSwiftVersion
                    defaultSeverity = doc.defaultSeverity
                }
            } else {
                print("⚠️ generate-docs returned empty markdown for \(identifier)")
            }
        } catch {
            // Fall back to rules command if generate-docs fails
            print("⚠️ generate-docs failed for \(identifier), falling back to rules command: \(error.localizedDescription)")
        }
        
        // If generate-docs didn't provide examples, try the rules command as fallback
        if triggeringExamples.isEmpty && nonTriggeringExamples.isEmpty {
            let detailData = try await swiftLintCLI.executeRuleDetailCommand(ruleId: identifier)
            guard let detailText = String(data: detailData, encoding: .utf8) else {
                // Return basic rule if we can't parse details
                return Rule(
                    id: identifier,
                    name: name,
                    description: description,
                    category: category,
                    isOptIn: isOptIn,
                    severity: defaultSeverity,
                    parameters: nil,
                    triggeringExamples: [],
                    nonTriggeringExamples: [],
                    documentation: nil,
                    isEnabled: !isOptIn,
                    supportsAutocorrection: supportsAutocorrection,
                    minimumSwiftVersion: minimumSwiftVersion,
                    defaultSeverity: defaultSeverity,
                    markdownDocumentation: markdownDoc
                )
            }
            
            // Parse rule details from rules command output
            let lines = detailText.components(separatedBy: .newlines)
            
            // Parse name and description from first line: "Rule Name (identifier): Description"
            if let firstLine = lines.first, firstLine.contains("(") {
                let parts = firstLine.components(separatedBy: ":")
                if parts.count >= 2 {
                    let namePart = parts[0].trimmingCharacters(in: .whitespaces)
                    if let parenStart = namePart.range(of: "(") {
                        name = String(namePart[..<parenStart.lowerBound]).trimmingCharacters(in: .whitespaces)
                    }
                    if description == "No description available" {
                        description = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            
            // Parse examples
            var inTriggeringExamples = false
            var inNonTriggeringExamples = false
            var currentExample: [String] = []
            
            for line in lines {
                if line.contains("Triggering Examples") {
                    inTriggeringExamples = true
                    inNonTriggeringExamples = false
                    continue
                } else if line.contains("Non-Triggering Examples") || line.contains("Non Triggering Examples") {
                    inNonTriggeringExamples = true
                    inTriggeringExamples = false
                    continue
                } else if line.contains("Configuration") || line.isEmpty {
                    if !currentExample.isEmpty {
                        let example = currentExample.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                        if inTriggeringExamples && !example.isEmpty {
                            triggeringExamples.append(example)
                        } else if inNonTriggeringExamples && !example.isEmpty {
                            nonTriggeringExamples.append(example)
                        }
                        currentExample = []
                    }
                    inTriggeringExamples = false
                    inNonTriggeringExamples = false
                    continue
                }
                
                if inTriggeringExamples || inNonTriggeringExamples {
                    // Skip example markers and empty lines
                    if line.contains("Example #") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                        if !currentExample.isEmpty {
                            let example = currentExample.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                            if inTriggeringExamples && !example.isEmpty {
                                triggeringExamples.append(example)
                            } else if inNonTriggeringExamples && !example.isEmpty {
                                nonTriggeringExamples.append(example)
                            }
                            currentExample = []
                        }
                        continue
                    }
                    
                    // Remove violation markers (↓)
                    let cleanLine = line.replacingOccurrences(of: "↓", with: "").trimmingCharacters(in: .whitespaces)
                    if !cleanLine.isEmpty {
                        currentExample.append(cleanLine)
                    }
                }
            }
            
            // Add last example if any
            if !currentExample.isEmpty {
                let example = currentExample.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if inTriggeringExamples && !example.isEmpty {
                    triggeringExamples.append(example)
                } else if inNonTriggeringExamples && !example.isEmpty {
                    nonTriggeringExamples.append(example)
                }
            }
        }
        
        return Rule(
            id: identifier,
            name: name,
            description: description,
            category: category,
            isOptIn: isOptIn,
            severity: defaultSeverity,
            parameters: nil,
            triggeringExamples: triggeringExamples,
            nonTriggeringExamples: nonTriggeringExamples,
            documentation: nil,
            isEnabled: !isOptIn,
            supportsAutocorrection: supportsAutocorrection,
            minimumSwiftVersion: minimumSwiftVersion,
            defaultSeverity: defaultSeverity,
            markdownDocumentation: markdownDoc
        )
    }
}

