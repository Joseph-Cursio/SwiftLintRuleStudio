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
    
    let swiftLintCLI: SwiftLintCLIProtocol
    let cacheManager: CacheManagerProtocol
    var backgroundLoadingTask: Task<Void, Never>?
    
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

    func updateRules(_ updatedRules: [Rule]) {
        rules = updatedRules
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
                var updatedRules = rules
                updatedRules[index] = detailedRule
                updateRules(updatedRules)
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
}
