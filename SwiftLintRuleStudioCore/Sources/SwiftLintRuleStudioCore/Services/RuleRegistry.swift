//
//  RuleRegistry.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import Observation

/// Service for managing SwiftLint rules metadata
@MainActor
public protocol RuleRegistryProtocol {
    func loadRules() async throws -> [Rule]
    func getRule(id: String) -> Rule?
    func refreshRules() async throws
    var rules: [Rule] { get }
}

@MainActor
@Observable
public class RuleRegistry: RuleRegistryProtocol {
    public private(set) var rules: [Rule] = []
    public private(set) var isLoading: Bool = false
    public private(set) var error: Error?

    public let swiftLintCLI: SwiftLintCLIProtocol
    public let cacheManager: CacheManagerProtocol
    nonisolated(unsafe) var backgroundLoadingTask: Task<Void, Never>?

    public init(swiftLintCLI: SwiftLintCLIProtocol, cacheManager: CacheManagerProtocol) {
        self.swiftLintCLI = swiftLintCLI
        self.cacheManager = cacheManager
    }

    deinit {
        backgroundLoadingTask?.cancel()
    }

    public nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    public func loadRules() async throws -> [Rule] {
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

    public func getRule(id: String) -> Rule? {
        rules.first { $0.id == id }
    }

    public func updateRules(_ updatedRules: [Rule]) {
        rules = updatedRules
    }

    /// Fetch details for a specific rule on demand (useful when rule was loaded without details)
    public func fetchRuleDetailsIfNeeded(id: String) async {
        guard let rule = getRule(id: id),
              rule.markdownDocumentation == nil || rule.markdownDocumentation?.isEmpty == true else {
            // Rule already has documentation
            return
        }

        guard let detailedRule = try? await fetchRuleDetails(
            identifier: rule.id, category: rule.category, isOptIn: rule.isOptIn
        ) else { return }

        // Update the rule in the rules array
        if let index = rules.firstIndex(where: { $0.id == id }) {
            var updatedRules = rules
            updatedRules[index] = detailedRule
            updateRules(updatedRules)
            // @Observable automatically notifies observers on mutation — no manual send needed
        }
    }

    public func refreshRules() async throws {
        _ = try await loadRules()
    }

    /// Update each rule's `isEnabled` to match the actual YAML configuration.
    public func syncEnabledStates(with config: YAMLConfigurationEngine.YAMLConfig) {
        var updated = rules
        for index in updated.indices {
            updated[index].isEnabled = isRuleEnabled(updated[index], config: config)
        }
        rules = updated
    }

    private func isRuleEnabled(
        _ rule: Rule,
        config: YAMLConfigurationEngine.YAMLConfig
    ) -> Bool {
        if let onlyRules = config.onlyRules {
            return onlyRules.contains(rule.id)
        }
        if rule.isOptIn {
            if let ruleConfig = config.rules[rule.id],
               ruleConfig.enabled == false {
                return false
            }
            if let optInRules = config.optInRules {
                return optInRules.contains(rule.id)
            }
            return false
        }
        if config.disabledRules?.contains(rule.id) == true {
            return false
        }
        if let ruleConfig = config.rules[rule.id] {
            return ruleConfig.enabled
        }
        return true
    }

#if DEBUG
    /// Test-only helper to inject rules without hitting SwiftLint CLI.
    public func setRulesForTesting(_ rules: [Rule]) {
        self.rules = rules
    }
#endif
}
