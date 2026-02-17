//
//  VersionCompatibilityChecker.swift
//  SwiftLintRuleStudio
//
//  Service to check config compatibility with the installed SwiftLint version
//

import Foundation

// MARK: - Report Types

struct DeprecatedRuleInfo: Sendable, Identifiable {
    let id: String
    let ruleId: String
    let deprecatedInVersion: String
    let replacement: String?
    let message: String
}

struct RemovedRuleInfo: Sendable, Identifiable {
    let id: String
    let ruleId: String
    let removedInVersion: String
    let replacement: String?
    let message: String
}

struct RenamedRuleInfo: Sendable, Identifiable {
    let id: String
    let oldRuleId: String
    let newRuleId: String
}

struct CompatibilityReport: Sendable {
    let swiftLintVersion: String
    let deprecatedRules: [DeprecatedRuleInfo]
    let removedRules: [RemovedRuleInfo]
    let renamedRules: [RenamedRuleInfo]
    let availableNewRules: [String]

    var hasIssues: Bool {
        !deprecatedRules.isEmpty || !removedRules.isEmpty || !renamedRules.isEmpty
    }

    var totalIssueCount: Int {
        deprecatedRules.count + removedRules.count + renamedRules.count
    }
}

// MARK: - Protocol

protocol VersionCompatibilityCheckerProtocol: Sendable {
    func checkCompatibility(
        config: YAMLConfigurationEngine.YAMLConfig,
        swiftLintVersion: String
    ) -> CompatibilityReport
}

// MARK: - Implementation

final class VersionCompatibilityChecker: VersionCompatibilityCheckerProtocol {

    func checkCompatibility(
        config: YAMLConfigurationEngine.YAMLConfig,
        swiftLintVersion: String
    ) -> CompatibilityReport {
        let allConfigRuleIds = collectAllRuleIds(from: config)

        let deprecated = findDeprecatedRules(in: allConfigRuleIds, version: swiftLintVersion)
        let removed = findRemovedRules(in: allConfigRuleIds, version: swiftLintVersion)
        let renamed = findRenamedRules(in: allConfigRuleIds)
        let newRules = findNewRulesAvailable(configRuleIds: allConfigRuleIds, version: swiftLintVersion)

        return CompatibilityReport(
            swiftLintVersion: swiftLintVersion,
            deprecatedRules: deprecated,
            removedRules: removed,
            renamedRules: renamed,
            availableNewRules: newRules
        )
    }

    // MARK: - Private

    private func collectAllRuleIds(from config: YAMLConfigurationEngine.YAMLConfig) -> Set<String> {
        var ids = Set(config.rules.keys)
        if let disabled = config.disabledRules {
            ids.formUnion(disabled)
        }
        if let optIn = config.optInRules {
            ids.formUnion(optIn)
        }
        if let analyzer = config.analyzerRules {
            ids.formUnion(analyzer)
        }
        if let only = config.onlyRules {
            ids.formUnion(only)
        }
        return ids
    }

    private func findDeprecatedRules(in ruleIds: Set<String>, version: String) -> [DeprecatedRuleInfo] {
        var results: [DeprecatedRuleInfo] = []
        for ruleId in ruleIds.sorted() {
            if let entry = SwiftLintDeprecations.deprecatedRules[ruleId] {
                // Only report if current version is >= deprecated version
                if !SwiftLintDeprecations.isVersion(version, lessThan: entry.deprecatedInVersion) {
                    // Skip if also removed (will appear in removed list)
                    if SwiftLintDeprecations.removedRules[ruleId] != nil {
                        let removedEntry = SwiftLintDeprecations.removedRules[ruleId]!
                        if !SwiftLintDeprecations.isVersion(version, lessThan: removedEntry.removedInVersion) {
                            continue // Will appear in removed rules
                        }
                    }
                    results.append(DeprecatedRuleInfo(
                        id: ruleId,
                        ruleId: ruleId,
                        deprecatedInVersion: entry.deprecatedInVersion,
                        replacement: entry.replacement,
                        message: entry.message
                    ))
                }
            }
        }
        return results
    }

    private func findRemovedRules(in ruleIds: Set<String>, version: String) -> [RemovedRuleInfo] {
        var results: [RemovedRuleInfo] = []
        for ruleId in ruleIds.sorted() {
            if let entry = SwiftLintDeprecations.removedRules[ruleId] {
                if !SwiftLintDeprecations.isVersion(version, lessThan: entry.removedInVersion) {
                    results.append(RemovedRuleInfo(
                        id: ruleId,
                        ruleId: ruleId,
                        removedInVersion: entry.removedInVersion,
                        replacement: entry.replacement,
                        message: entry.message
                    ))
                }
            }
        }
        return results
    }

    private func findRenamedRules(in ruleIds: Set<String>) -> [RenamedRuleInfo] {
        var results: [RenamedRuleInfo] = []
        for ruleId in ruleIds.sorted() {
            if let newId = SwiftLintDeprecations.renamedRules[ruleId], newId != ruleId {
                results.append(RenamedRuleInfo(
                    id: ruleId,
                    oldRuleId: ruleId,
                    newRuleId: newId
                ))
            }
        }
        return results
    }

    private func findNewRulesAvailable(configRuleIds: Set<String>, version: String) -> [String] {
        // Gather all rules added up to the current version
        var allAvailable: Set<String> = []
        for (ver, rules) in SwiftLintDeprecations.versionRuleAdditions {
            if !SwiftLintDeprecations.isVersion(version, lessThan: ver) {
                allAvailable.formUnion(rules)
            }
        }
        // Return rules that exist in SwiftLint but aren't in the config
        return allAvailable.subtracting(configRuleIds).sorted()
    }
}
