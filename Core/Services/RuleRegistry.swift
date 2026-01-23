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
        let text = try decodeRuleText(from: data)
        print("SwiftLint output (first 500 chars):\n\(String(text.prefix(500)))")

        let rules = parseRulesTable(from: text)
        print("Parsed \(rules.count) rules from SwiftLint output")

        guard !rules.isEmpty else {
            throw NSError(
                domain: "RuleRegistry",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No rules found in SwiftLint output. Make sure SwiftLint is installed and accessible."]
            )
        }

        let updatedRules = await updateRulesWithDetails(rules)

        let remainingRules = Array(rules.suffix(from: min(20, rules.count)))
        if !remainingRules.isEmpty {
            startBackgroundLoading(for: remainingRules, startingIndex: min(20, rules.count))
        }

        return updatedRules
    }

    private func decodeRuleText(from data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "RuleRegistry",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode SwiftLint output"]
            )
        }
        return text
    }

    private func parseRulesTable(from text: String) -> [Rule] {
        text.components(separatedBy: .newlines).compactMap(parseRuleLine(from:))
    }

    private func parseRuleLine(from line: String) -> Rule? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard shouldParseRuleLine(trimmed) else { return nil }

        let columns = trimmed.split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard columns.count >= 5 else {
            print("Skipping line (not enough columns: \(columns.count)): \(String(trimmed.prefix(80)))")
            return nil
        }

        let identifier = columns[0]
        guard !identifier.isEmpty && !identifier.contains("─") else { return nil }

        let optInStr = columns.count > 1 ? columns[1].lowercased() : "no"
        let isOptIn = optInStr == "yes"
        let kindStr = columns.count > 4 ? columns[4].lowercased() : "style"
        let category = mapCategory(kindStr)

        return Rule(
            id: identifier,
            name: identifier.replacingOccurrences(of: "_", with: " ").capitalized,
            description: "Loading...",
            category: category,
            isOptIn: isOptIn,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: !isOptIn,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: nil
        )
    }

    private func shouldParseRuleLine(_ trimmed: String) -> Bool {
        if trimmed.isEmpty || trimmed.hasPrefix("+") || !trimmed.hasPrefix("|") {
            return false
        }
        return !trimmed.lowercased().contains("identifier")
    }

    private func updateRulesWithDetails(_ rules: [Rule]) async -> [Rule] {
        let rulesToFetchDetails = Array(rules.prefix(20))
        var updatedRules = rules

        await withTaskGroup(of: (Int, Rule).self) { group in
            for (index, rule) in rulesToFetchDetails.enumerated() {
                group.addTask { [weak self] in
                    guard let self = self else { return (index, rule) }
                    return await self.fetchDetailedRuleResult(rule: rule, index: index)
                }
            }

            for await (index, detailedRule) in group {
                updatedRules[index] = detailedRule
                self.rules = updatedRules
            }
        }

        return updatedRules
    }

    private func fetchDetailedRuleResult(rule: Rule, index: Int) async -> (Int, Rule) {
        do {
            let detailedRule = try await fetchRuleDetailsWithTimeout(rule: rule)
            return (index, detailedRule)
        } catch {
            print("⚠️ Failed to fetch details for rule \(rule.id): \(error.localizedDescription)")
            return (index, rule)
        }
    }

    private func fetchRuleDetailsWithTimeout(rule: Rule) async throws -> Rule {
        try await withThrowingTaskGroup(of: Rule.self) { timeoutGroup in
            timeoutGroup.addTask {
                try await self.fetchRuleDetails(
                    identifier: rule.id,
                    category: rule.category,
                    isOptIn: rule.isOptIn
                )
            }
            timeoutGroup.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw NSError(
                    domain: "RuleRegistry",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Rule detail fetch timed out for \(rule.id)"]
                )
            }

            guard let result = try await timeoutGroup.next() else {
                throw NSError(
                    domain: "RuleRegistry",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Rule detail fetch cancelled for \(rule.id)"]
                )
            }
            timeoutGroup.cancelAll()
            return result
        }
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
                let ruleData = batch.enumerated().map { offset, rule in
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
                                            throw NSError(
                                                domain: "RuleRegistry",
                                                code: 3,
                                                userInfo: [NSLocalizedDescriptionKey: "Rule detail fetch timed out for \(ruleId)"]
                                            )
                                        }
                                        
                                        // Return first completed result (either success or timeout)
                                        guard let result = try await timeoutGroup.next() else {
                                            throw NSError(
                                                domain: "RuleRegistry",
                                                code: 4,
                                                userInfo: [NSLocalizedDescriptionKey: "Rule detail fetch cancelled for \(ruleId)"]
                                            )
                                        }
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
        var state = RuleDetailsState(identifier: identifier, isOptIn: isOptIn)
        await populateFromDocs(ruleId: identifier, swiftLintCLI: swiftLintCLI, state: &state)
        if state.triggeringExamples.isEmpty && state.nonTriggeringExamples.isEmpty {
            try await populateFromRuleDetails(ruleId: identifier, swiftLintCLI: swiftLintCLI, state: &state)
        }
        return state.asRule(category: category)
    }

    private struct RuleDetailsState {
        let identifier: String
        let isOptIn: Bool
        var name: String
        var description: String
        var triggeringExamples: [String]
        var nonTriggeringExamples: [String]
        var supportsAutocorrection: Bool
        var minimumSwiftVersion: String?
        var defaultSeverity: Severity?
        var markdownDoc: String?

        init(identifier: String, isOptIn: Bool) {
            self.identifier = identifier
            self.isOptIn = isOptIn
            name = identifier.replacingOccurrences(of: "_", with: " ").capitalized
            description = "No description available"
            triggeringExamples = []
            nonTriggeringExamples = []
            supportsAutocorrection = false
            minimumSwiftVersion = nil
            defaultSeverity = nil
            markdownDoc = nil
        }

        mutating func apply(_ doc: ParsedRuleDocumentation) {
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

        func asRule(category: RuleCategory) -> Rule {
            Rule(
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

    private static func populateFromDocs(
        ruleId: String,
        swiftLintCLI: SwiftLintCLIProtocol,
        state: inout RuleDetailsState
    ) async {
        do {
            let markdown = try await swiftLintCLI.generateDocsForRule(ruleId: ruleId)
            state.markdownDoc = markdown
            guard !markdown.isEmpty else {
                print("⚠️ generate-docs returned empty markdown for \(ruleId)")
                return
            }
            let parsedDoc = RuleDocumentationParser.parse(markdown: markdown)
            state.apply(parsedDoc)
        } catch {
            print("⚠️ generate-docs failed for \(ruleId), falling back to rules command: \(error.localizedDescription)")
        }
    }

    private static func populateFromRuleDetails(
        ruleId: String,
        swiftLintCLI: SwiftLintCLIProtocol,
        state: inout RuleDetailsState
    ) async throws {
        let detailData = try await swiftLintCLI.executeRuleDetailCommand(ruleId: ruleId)
        guard let detailText = String(data: detailData, encoding: .utf8) else {
            return
        }
        let lines = detailText.components(separatedBy: .newlines)
        applyRuleHeader(lines: lines, state: &state)
        applyRuleExamples(lines: lines, state: &state)
    }

    private static func applyRuleHeader(lines: [String], state: inout RuleDetailsState) {
        guard let firstLine = lines.first, firstLine.contains("(") else { return }
        let parts = firstLine.components(separatedBy: ":")
        guard parts.count >= 2 else { return }
        let namePart = parts[0].trimmingCharacters(in: .whitespaces)
        if let parenStart = namePart.range(of: "(") {
            state.name = String(namePart[..<parenStart.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        if state.description == "No description available" {
            state.description = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
        }
    }

    private static func applyRuleExamples(lines: [String], state: inout RuleDetailsState) {
        var inTriggeringExamples = false
        var inNonTriggeringExamples = false
        var currentExample: [String] = []

        for line in lines {
            if line.contains("Triggering Examples") {
                inTriggeringExamples = true
                inNonTriggeringExamples = false
                continue
            }
            if line.contains("Non-Triggering Examples") || line.contains("Non Triggering Examples") {
                inNonTriggeringExamples = true
                inTriggeringExamples = false
                continue
            }
            if line.contains("Configuration") || line.isEmpty {
                flushExample(
                    inTriggeringExamples: &inTriggeringExamples,
                    inNonTriggeringExamples: &inNonTriggeringExamples,
                    currentExample: &currentExample,
                    state: &state
                )
                continue
            }
            guard inTriggeringExamples || inNonTriggeringExamples else { continue }

            if line.contains("Example #") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushExample(
                    inTriggeringExamples: &inTriggeringExamples,
                    inNonTriggeringExamples: &inNonTriggeringExamples,
                    currentExample: &currentExample,
                    state: &state
                )
                continue
            }

            let cleanLine = line.replacingOccurrences(of: "↓", with: "").trimmingCharacters(in: .whitespaces)
            if !cleanLine.isEmpty {
                currentExample.append(cleanLine)
            }
        }

        flushExample(
            inTriggeringExamples: &inTriggeringExamples,
            inNonTriggeringExamples: &inNonTriggeringExamples,
            currentExample: &currentExample,
            state: &state
        )
    }

    private static func flushExample(
        inTriggeringExamples: inout Bool,
        inNonTriggeringExamples: inout Bool,
        currentExample: inout [String],
        state: inout RuleDetailsState
    ) {
        guard !currentExample.isEmpty else {
            inTriggeringExamples = false
            inNonTriggeringExamples = false
            return
        }
        let example = currentExample.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if inTriggeringExamples && !example.isEmpty {
            state.triggeringExamples.append(example)
        } else if inNonTriggeringExamples && !example.isEmpty {
            state.nonTriggeringExamples.append(example)
        }
        currentExample = []
        inTriggeringExamples = false
        inNonTriggeringExamples = false
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
        return try await Self.fetchRuleDetailsHelper(
            identifier: identifier,
            category: category,
            isOptIn: isOptIn,
            swiftLintCLI: swiftLintCLI
        )
    }
}
