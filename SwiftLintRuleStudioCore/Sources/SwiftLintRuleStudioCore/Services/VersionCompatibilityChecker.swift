//
//  VersionCompatibilityChecker.swift
//  SwiftLintRuleStudio
//
//  Service to check config compatibility with the installed SwiftLint version
//

import Foundation

// MARK: - Report Types

public struct DeprecatedRuleInfo: Sendable, Identifiable {
    public let id: String
    public let ruleId: String
    public let deprecatedInVersion: String
    public let replacement: String?
    public let message: String

    public init(
        id: String,
        ruleId: String,
        deprecatedInVersion: String,
        replacement: String?,
        message: String
    ) {
        self.id = id
        self.ruleId = ruleId
        self.deprecatedInVersion = deprecatedInVersion
        self.replacement = replacement
        self.message = message
    }
}

public struct RemovedRuleInfo: Sendable, Identifiable {
    public let id: String
    public let ruleId: String
    public let removedInVersion: String
    public let replacement: String?
    public let message: String

    public init(
        id: String,
        ruleId: String,
        removedInVersion: String,
        replacement: String?,
        message: String
    ) {
        self.id = id
        self.ruleId = ruleId
        self.removedInVersion = removedInVersion
        self.replacement = replacement
        self.message = message
    }
}

public struct RenamedRuleInfo: Sendable, Identifiable {
    public let id: String
    public let oldRuleId: String
    public let newRuleId: String

    public init(
        id: String,
        oldRuleId: String,
        newRuleId: String
    ) {
        self.id = id
        self.oldRuleId = oldRuleId
        self.newRuleId = newRuleId
    }
}

public struct CompatibilityReport: Sendable {
    public let swiftLintVersion: String
    public let deprecatedRules: [DeprecatedRuleInfo]
    public let removedRules: [RemovedRuleInfo]
    public let renamedRules: [RenamedRuleInfo]
    public let availableNewRules: [String]

    public var hasIssues: Bool {
        !deprecatedRules.isEmpty || !removedRules.isEmpty || !renamedRules.isEmpty
    }

    public var totalIssueCount: Int {
        deprecatedRules.count + removedRules.count + renamedRules.count
    }

    public init(
        swiftLintVersion: String,
        deprecatedRules: [DeprecatedRuleInfo],
        removedRules: [RemovedRuleInfo],
        renamedRules: [RenamedRuleInfo],
        availableNewRules: [String]
    ) {
        self.swiftLintVersion = swiftLintVersion
        self.deprecatedRules = deprecatedRules
        self.removedRules = removedRules
        self.renamedRules = renamedRules
        self.availableNewRules = availableNewRules
    }
}

// MARK: - Protocol

public protocol VersionCompatibilityCheckerProtocol: Sendable {
    func checkCompatibility(
        config: YAMLConfigurationEngine.YAMLConfig,
        swiftLintVersion: String
    ) -> CompatibilityReport
}

// MARK: - Implementation

public final class VersionCompatibilityChecker: VersionCompatibilityCheckerProtocol {

    public func checkCompatibility(
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
                    if let removedEntry = SwiftLintDeprecations.removedRules[ruleId] {
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
        for (ver, rules) in SwiftLintDeprecations.versionRuleAdditions
            where !SwiftLintDeprecations.isVersion(version, lessThan: ver) {
            allAvailable.formUnion(rules)
        }
        // Return rules that exist in SwiftLint but aren't in the config
        return allAvailable.subtracting(configRuleIds).sorted()
    }
}
