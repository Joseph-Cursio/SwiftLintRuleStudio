//
//  MigrationAssistant.swift
//  SwiftLintRuleStudio
//
//  Service for migrating SwiftLint configs between versions
//

import Foundation

// MARK: - Types

public enum MigrationStep: Sendable, Identifiable, Equatable {
    case renameRule(from: String, newName: String)
    case removeDeprecatedRule(ruleId: String, reason: String)
    case updateParameter(ruleId: String, oldParam: String, newParam: String)
    case manualAction(description: String)

    public var id: String {
        switch self {
        case .renameRule(let from, let newName): return "rename-\(from)-\(newName)"
        case .removeDeprecatedRule(let ruleId, _): return "remove-\(ruleId)"
        case .updateParameter(let ruleId, let old, _): return "param-\(ruleId)-\(old)"
        case .manualAction(let desc): return "manual-\(desc.hashValue)"
        }
    }

    public var description: String {
        switch self {
        case .renameRule(let from, let newName):
            return "Rename '\(from)' to '\(newName)'"
        case .removeDeprecatedRule(let ruleId, let reason):
            return "Remove '\(ruleId)': \(reason)"
        case .updateParameter(let ruleId, let oldParam, let newParam):
            return "Update parameter on '\(ruleId)': '\(oldParam)' -> '\(newParam)'"
        case .manualAction(let desc):
            return desc
        }
    }

    public var canAutoApply: Bool {
        switch self {
        case .renameRule, .removeDeprecatedRule, .updateParameter: return true
        case .manualAction: return false
        }
    }

    public var iconName: String {
        switch self {
        case .renameRule: return "arrow.right"
        case .removeDeprecatedRule: return "trash"
        case .updateParameter: return "slider.horizontal.3"
        case .manualAction: return "exclamationmark.circle"
        }
    }
}

public struct MigrationPlan: Sendable, Equatable {
    public let fromVersion: String
    public let toVersion: String
    public let steps: [MigrationStep]

    public var totalSteps: Int { steps.count }
    public var canAutoApply: Bool { steps.allSatisfy(\.canAutoApply) }
    public var autoApplyableSteps: [MigrationStep] { steps.filter(\.canAutoApply) }
    public var manualSteps: [MigrationStep] { steps.filter { !$0.canAutoApply } }

    public init(
        fromVersion: String,
        toVersion: String,
        steps: [MigrationStep]
    ) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.steps = steps
    }
}

// MARK: - Protocol

public protocol MigrationAssistantProtocol: Sendable {
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

public final class MigrationAssistant: MigrationAssistantProtocol {

    public func detectMigrations(
        config: YAMLConfigurationEngine.YAMLConfig,
        fromVersion: String,
        toVersion: String
    ) -> MigrationPlan {
        var steps: [MigrationStep] = []

        let allRuleIds = config.ruleIds

        // Check renamed rules. A rename is offered only once the target version has the new name:
        // `variable_name` → `identifier_name` arrived in 0.25.0, so a 0.20 → 0.22 migration that
        // renamed it would leave a rule 0.22 does not know. The deprecation table carries the version
        // a rule was renamed in, and supplies a target for any deprecated rule the rename table lacks.
        for ruleId in allRuleIds.sorted() {
            let deprecation = SwiftLintDeprecations.deprecatedRules[ruleId]
            guard let newId = SwiftLintDeprecations.renamedRules[ruleId] ?? deprecation?.replacement,
                  newId != ruleId else { continue }
            if let renamedIn = deprecation?.deprecatedInVersion,
               SwiftLintDeprecations.isVersion(toVersion, lessThan: renamedIn) {
                continue
            }
            steps.append(.renameRule(from: ruleId, newName: newId))
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

    public func applyMigration(
        _ plan: MigrationPlan,
        to config: inout YAMLConfigurationEngine.YAMLConfig
    ) {
        for step in plan.autoApplyableSteps {
            applyStep(step, to: &config)
        }
    }

    // MARK: - Private

    private func applyStep(_ step: MigrationStep, to config: inout YAMLConfigurationEngine.YAMLConfig) {
        switch step {
        case .renameRule(let from, let newName):
            // Rename in rules dict
            if let ruleConfig = config.rules[from] {
                config.rules.removeValue(forKey: from)
                config.rules[newName] = ruleConfig
            }
            // Rename in list fields
            replaceInList(&config.disabledRules, old: from, new: newName)
            replaceInList(&config.optInRules, old: from, new: newName)
            replaceInList(&config.analyzerRules, old: from, new: newName)
            replaceInList(&config.onlyRules, old: from, new: newName)

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
