//
//  MigrationAssistant.swift
//  SwiftLintRuleStudio
//
//  Service for migrating SwiftLint configs between versions
//

import Foundation

// MARK: - Types

enum MigrationStep: Sendable, Identifiable {
    case renameRule(from: String, to: String)
    case removeDeprecatedRule(ruleId: String, reason: String)
    case updateParameter(ruleId: String, oldParam: String, newParam: String)
    case manualAction(description: String)

    var id: String {
        switch self {
        case .renameRule(let from, let to): return "rename-\(from)-\(to)"
        case .removeDeprecatedRule(let ruleId, _): return "remove-\(ruleId)"
        case .updateParameter(let ruleId, let old, _): return "param-\(ruleId)-\(old)"
        case .manualAction(let desc): return "manual-\(desc.hashValue)"
        }
    }

    var description: String {
        switch self {
        case .renameRule(let from, let to):
            return "Rename '\(from)' to '\(to)'"
        case .removeDeprecatedRule(let ruleId, let reason):
            return "Remove '\(ruleId)': \(reason)"
        case .updateParameter(let ruleId, let oldParam, let newParam):
            return "Update parameter on '\(ruleId)': '\(oldParam)' -> '\(newParam)'"
        case .manualAction(let desc):
            return desc
        }
    }

    var canAutoApply: Bool {
        switch self {
        case .renameRule, .removeDeprecatedRule, .updateParameter: return true
        case .manualAction: return false
        }
    }

    var iconName: String {
        switch self {
        case .renameRule: return "arrow.right"
        case .removeDeprecatedRule: return "trash"
        case .updateParameter: return "slider.horizontal.3"
        case .manualAction: return "exclamationmark.circle"
        }
    }
}

struct MigrationPlan: Sendable {
    let fromVersion: String
    let toVersion: String
    let steps: [MigrationStep]

    var totalSteps: Int { steps.count }
    var canAutoApply: Bool { steps.allSatisfy(\.canAutoApply) }
    var autoApplyableSteps: [MigrationStep] { steps.filter(\.canAutoApply) }
    var manualSteps: [MigrationStep] { steps.filter { !$0.canAutoApply } }
}

// MARK: - Protocol

protocol MigrationAssistantProtocol: Sendable {
    func detectMigrations(
        config: YAMLConfigurationEngine.YAMLConfig,
        fromVersion: String,
        toVersion: String
    ) -> MigrationPlan

    func applyMigration(
        _ plan: MigrationPlan,
        to config: inout YAMLConfigurationEngine.YAMLConfig
    )
}

// MARK: - Implementation

final class MigrationAssistant: MigrationAssistantProtocol {

    func detectMigrations(
        config: YAMLConfigurationEngine.YAMLConfig,
        fromVersion: String,
        toVersion: String
    ) -> MigrationPlan {
        var steps: [MigrationStep] = []

        let allRuleIds = collectAllRuleIds(from: config)

        // Check renamed rules
        for ruleId in allRuleIds.sorted() {
            if let newId = SwiftLintDeprecations.renamedRules[ruleId], newId != ruleId {
                steps.append(.renameRule(from: ruleId, to: newId))
            }
        }

        // Check removed rules
        for ruleId in allRuleIds.sorted() {
            if let entry = SwiftLintDeprecations.removedRules[ruleId] {
                if SwiftLintDeprecations.isVersion(fromVersion, lessThan: entry.removedInVersion)
                    && !SwiftLintDeprecations.isVersion(toVersion, lessThan: entry.removedInVersion) {
                    // Only add if not already handled by rename
                    if !steps.contains(where: {
                        if case .renameRule(let from, _) = $0, from == ruleId { return true }
                        return false
                    }) {
                        steps.append(.removeDeprecatedRule(ruleId: ruleId, reason: entry.message))
                    }
                }
            }
        }

        // Check deprecated rules
        for ruleId in allRuleIds.sorted() {
            if let entry = SwiftLintDeprecations.deprecatedRules[ruleId] {
                if SwiftLintDeprecations.isVersion(fromVersion, lessThan: entry.deprecatedInVersion)
                    && !SwiftLintDeprecations.isVersion(toVersion, lessThan: entry.deprecatedInVersion) {
                    // Only add if not already handled by rename or removal
                    let alreadyHandled = steps.contains(where: {
                        switch $0 {
                        case .renameRule(let from, _): return from == ruleId
                        case .removeDeprecatedRule(let id, _): return id == ruleId
                        default: return false
                        }
                    })
                    if !alreadyHandled, let replacement = entry.replacement {
                        steps.append(.renameRule(from: ruleId, to: replacement))
                    }
                }
            }
        }

        // Check for new rules available (informational)
        let newRules = SwiftLintDeprecations.rulesAdded(from: fromVersion, to: toVersion)
        if !newRules.isEmpty {
            steps.append(.manualAction(
                description: "New rules available: \(newRules.joined(separator: ", ")). Consider enabling them."
            ))
        }

        return MigrationPlan(
            fromVersion: fromVersion,
            toVersion: toVersion,
            steps: steps
        )
    }

    func applyMigration(
        _ plan: MigrationPlan,
        to config: inout YAMLConfigurationEngine.YAMLConfig
    ) {
        for step in plan.autoApplyableSteps {
            applyStep(step, to: &config)
        }
    }

    // MARK: - Private

    private func collectAllRuleIds(from config: YAMLConfigurationEngine.YAMLConfig) -> Set<String> {
        var ids = Set(config.rules.keys)
        if let disabled = config.disabledRules { ids.formUnion(disabled) }
        if let optIn = config.optInRules { ids.formUnion(optIn) }
        if let analyzer = config.analyzerRules { ids.formUnion(analyzer) }
        if let only = config.onlyRules { ids.formUnion(only) }
        return ids
    }

    private func applyStep(_ step: MigrationStep, to config: inout YAMLConfigurationEngine.YAMLConfig) {
        switch step {
        case .renameRule(let from, let to):
            // Rename in rules dict
            if let ruleConfig = config.rules[from] {
                config.rules.removeValue(forKey: from)
                config.rules[to] = ruleConfig
            }
            // Rename in list fields
            replaceInList(&config.disabledRules, old: from, new: to)
            replaceInList(&config.optInRules, old: from, new: to)
            replaceInList(&config.analyzerRules, old: from, new: to)
            replaceInList(&config.onlyRules, old: from, new: to)

        case .removeDeprecatedRule(let ruleId, _):
            config.rules.removeValue(forKey: ruleId)
            removeFromList(&config.disabledRules, item: ruleId)
            removeFromList(&config.optInRules, item: ruleId)
            removeFromList(&config.analyzerRules, item: ruleId)
            removeFromList(&config.onlyRules, item: ruleId)

        case .updateParameter(let ruleId, let oldParam, let newParam):
            if var params = config.rules[ruleId]?.parameters {
                if let value = params[oldParam] {
                    params.removeValue(forKey: oldParam)
                    params[newParam] = value
                    config.rules[ruleId]?.parameters = params
                }
            }

        case .manualAction:
            break // Manual actions are not auto-applied
        }
    }

    private func replaceInList(_ list: inout [String]?, old: String, new: String) {
        guard var items = list else { return }
        if let idx = items.firstIndex(of: old) {
            items[idx] = new
            list = items
        }
    }

    private func removeFromList(_ list: inout [String]?, item: String) {
        guard var items = list else { return }
        items.removeAll { $0 == item }
        list = items.isEmpty ? nil : items
    }
}
