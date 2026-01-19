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
    private var backgroundLoadingTask: Task<Void, Never>?
    
    init(swiftLintCLI: SwiftLintCLIProtocol, cacheManager: CacheManagerProtocol) {
        self.swiftLintCLI = swiftLintCLI
        self.cacheManager = cacheManager
    }
    
    func loadRules() async throws -> [Rule] {
        // Cancel any existing background loading
        backgroundLoadingTask?.cancel()
        backgroundLoadingTask = nil
        
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

#if DEBUG
    /// Test-only helper to inject rules without hitting SwiftLint CLI.
    func setRulesForTesting(_ rules: [Rule]) {
        self.rules = rules
    }
#endif
    
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
        // Use a timeout to prevent individual rule fetches from hanging indefinitely
        await withTaskGroup(of: (Int, Rule).self) { group in
            for (index, rule) in rulesToFetchDetails.enumerated() {
                group.addTask { [weak self] in
                    guard let self = self else {
                        return (index, rule)
                    }
                    do {
                        // Add timeout to prevent hanging (30 seconds per rule)
                        let detailedRule = try await withThrowingTaskGroup(of: Rule.self) { timeoutGroup in
                            // Start the actual fetch
                            timeoutGroup.addTask {
                                try await self.fetchRuleDetails(identifier: rule.id, category: rule.category, isOptIn: rule.isOptIn)
                            }
                            
                            // Start timeout task
                            timeoutGroup.addTask {
                                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                                throw NSError(domain: "RuleRegistry", code: 3, userInfo: [NSLocalizedDescriptionKey: "Rule detail fetch timed out for \(rule.id)"])
                            }
                            
                            // Return first completed result (either success or timeout)
                            let result = try await timeoutGroup.next()!
                            timeoutGroup.cancelAll()
                            return result
                        }
                        return (index, detailedRule)
                    } catch {
                        // Return original rule if detail fetch fails or times out
                        print("⚠️ Failed to fetch details for rule \(rule.id): \(error.localizedDescription)")
                        // Update description to indicate failure instead of "Loading..."
                        var failedRule = rule
                        // Note: Rule is a struct, so we can't modify it directly. We'll return it as-is.
                        return (index, rule)
                    }
                }
            }
            
            // Update rules as they complete (not all at once)
            for await (index, detailedRule) in group {
                updatedRules[index] = detailedRule
                // Update the published rules array immediately so UI updates
                self.rules = updatedRules
            }
        }
        
        // Start background loading for remaining rules
        let remainingRules = Array(rules.suffix(from: min(20, rules.count)))
        if !remainingRules.isEmpty {
            startBackgroundLoading(for: remainingRules, startingIndex: min(20, rules.count))
        }
        
        return updatedRules
    }
    
    /// Start background loading for remaining rules
    private func startBackgroundLoading(for rules: [Rule], startingIndex: Int) {
        // Cancel any existing background loading task
        backgroundLoadingTask?.cancel()
        
        // Capture dependencies needed (nonisolated to avoid data race warnings)
        nonisolated(unsafe) let swiftLintCLICapture = self.swiftLintCLI
        
        // Capture weak reference to self for updates (accessed only from MainActor)
        nonisolated(unsafe) weak var weakSelf = self
        
        // Extract rules data before detached task to avoid capturing MainActor-isolated state
        let rulesData = rules.map { rule in
            (id: rule.id, category: rule.category, isOptIn: rule.isOptIn)
        }
        
        // Start new background task using Task.detached to avoid MainActor blocking
        backgroundLoadingTask = Task.detached { @Sendable in
            // Load rules in smaller batches to avoid overwhelming the system
            let batchSize = 10
            var currentIndex = startingIndex
            
            for batchStart in stride(from: 0, to: rulesData.count, by: batchSize) {
                // Check if task was cancelled
                if Task.isCancelled {
                    break
                }
                
                let batchEnd = min(batchStart + batchSize, rulesData.count)
                let batch = Array(rulesData[batchStart..<batchEnd])
                
                // Extract rule data to avoid capturing in closures
                let ruleData = batch.enumerated().map { (offset, rule) in
                    (id: rule.id, category: rule.category, isOptIn: rule.isOptIn, index: currentIndex + offset)
                }
                currentIndex += batch.count
                
                // Load batch in parallel
                do {
                    try await withThrowingTaskGroup(of: (Int, Rule).self) { group in
                        for data in ruleData {
                            let index = data.index
                            let ruleId = data.id
                            let category = data.category
                            let isOptIn = data.isOptIn
                            
                            group.addTask { @Sendable in
                                do {
                                    // Add timeout to prevent hanging (30 seconds per rule)
                                    let detailedRule = try await withThrowingTaskGroup(of: Rule.self) { timeoutGroup in
                                        // Start the actual fetch - helper can be called directly since it's not MainActor-isolated
                                        timeoutGroup.addTask { @Sendable in
                                            return try await Self.fetchRuleDetailsHelper(
                                                identifier: ruleId,
                                                category: category,
                                                isOptIn: isOptIn,
                                                swiftLintCLI: swiftLintCLICapture
                                            )
                                        }
                                        
                                        // Start timeout task
                                        timeoutGroup.addTask { @Sendable in
                                            try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                                            throw NSError(domain: "RuleRegistry", code: 3, userInfo: [NSLocalizedDescriptionKey: "Rule detail fetch timed out for \(ruleId)"])
                                        }
                                        
                                        // Return first completed result (either success or timeout)
                                        let result = try await timeoutGroup.next()!
                                        timeoutGroup.cancelAll()
                                        return result
                                    }
                                    return (index, detailedRule)
                                } catch {
                                    // Return original rule if detail fetch fails or times out
                                    print("⚠️ Background fetch failed for rule \(ruleId): \(error.localizedDescription)")
                                    // Create a minimal rule as fallback
                                    let originalRule = Rule(
                                        id: ruleId,
                                        name: ruleId,
                                        description: "No description available",
                                        category: category,
                                        isOptIn: isOptIn,
                                        parameters: nil,
                                        triggeringExamples: [],
                                        nonTriggeringExamples: [],
                                        documentation: nil
                                    )
                                    return (index, originalRule)
                                }
                            }
                        }
                        
                        // Update rules as they complete - must be done on MainActor
                        do {
                            for try await (index, detailedRule) in group {
                                // Update on MainActor since rules is @Published
                                // Capture weakSelf again to avoid sending it across boundaries
                                nonisolated(unsafe) let capturedSelf = weakSelf
                                await MainActor.run { @Sendable in
                                    guard let self = capturedSelf, index < self.rules.count else { return }
                                    self.rules[index] = detailedRule
                                }
                            }
                        } catch {
                            print("⚠️ Error updating rules from background group: \(error.localizedDescription)")
                        }
                    }
                } catch {
                    print("⚠️ Error during background batch loading: \(error.localizedDescription)")
                }
                
                // Small delay between batches to avoid overwhelming SwiftLint
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            print("✅ Background loading completed for \(rulesData.count) rules")
        }
    }
    
    /// Helper to fetch rule details without requiring self (to avoid data race warnings)
    private static func fetchRuleDetailsHelper(
        identifier: String,
        category: RuleCategory,
        isOptIn: Bool,
        swiftLintCLI: SwiftLintCLIProtocol
    ) async throws -> Rule {
        // This is a static helper that duplicates the fetchRuleDetails logic
        // to avoid capturing self in concurrent contexts
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

