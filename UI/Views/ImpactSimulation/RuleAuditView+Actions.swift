//
//  RuleAuditView+Actions.swift
//  SwiftLintRuleStudio
//
//  Enabling rules from the audit: selection, configuration writes, and the
//  view state that goes with them. Running the audit lives in +Audit.
//

import SwiftLintRuleStudioCore
import SwiftUI

// MARK: - Enabling Rules

extension RuleAuditView {
    func resetAuditState() {
        auditEntries = []
        selectedRules.removeAll()
        expandedRuleId = nil
        totalSwiftFiles = 0
        auditDuration = 0
        auditProgress = nil
        isAuditing = false
        isEnabling = false
        errorMessage = nil
        showError = false
    }

    func selectAndEnableAllSafeRules() {
        selectedRules = Set(Self.safeDisabledRuleIds(in: auditEntries))
        enableSelectedRules()
    }

    /// The ids of entries that are currently disabled and carry no violations,
    /// i.e. the rules that can be turned on without creating work.
    static func safeDisabledRuleIds(in entries: [RuleAuditEntry]) -> [String] {
        entries
            .filter { !$0.isCurrentlyEnabled && $0.effortCategory == .safe }
            .map(\.id)
    }

    func enableSingleRule(_ rule: Rule) {
        selectedRules = [rule.id]
        enableSelectedRules()
    }

    func enableSelectedRules() {
        guard let configPath = Self.enableConfigPath(
            for: dependencies.workspaceManager.currentWorkspace
        ) else {
            return
        }

        isEnabling = true
        let ruleIds = selectedRules
        let knownRules = dependencies.ruleRegistry.rules

        Task {
            do {
                try Self.enableRules(ruleIds, configPath: configPath, rules: knownRules)

                // Update entries to reflect newly enabled rules
                auditEntries = Self.markEntriesEnabled(in: auditEntries, ruleIds: ruleIds)

                selectedRules.removeAll()
                isEnabling = false
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                isEnabling = false
            }
        }
    }

    /// The configuration file an enable action would write to: nil when there is
    /// no current workspace, or the workspace has no configuration file, in
    /// which case there is nothing to enable a rule in.
    static func enableConfigPath(for workspace: Workspace?) -> URL? {
        workspace?.configPath
    }

    /// Turns `ruleIds` on in the configuration at `configPath`, routing each by
    /// its classification in `rules`, backing the file up first, and announcing
    /// the change so the rest of the app re-reads the configuration.
    static func enableRules(
        _ ruleIds: Set<String>,
        configPath: URL,
        rules: [Rule]
    ) throws {
        let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
        try yamlEngine.load()
        var config = yamlEngine.getConfig()
        let classification = ruleClassification(from: rules)

        applyEnableRules(
            config: &config,
            ruleIds: Array(ruleIds),
            optInRuleIds: classification.optInRuleIds,
            analyzerRuleIds: classification.analyzerRuleIds
        )

        try yamlEngine.save(config: config, createBackup: true)
        postRuleChangeNotification(ruleIds: Array(ruleIds))
    }

    /// Splits `rules` into the opt-in and analyzer id sets that both the enable
    /// path and the simulator need. Analyzer rules are kept out of the opt-in
    /// set so every rule is routed to exactly one list.
    static func ruleClassification(from rules: [Rule]) -> RuleClassification {
        RuleClassification(
            optInRuleIds: Set(rules.filter { $0.isOptIn && !$0.isAnalyzer }.map(\.id)),
            analyzerRuleIds: Set(rules.filter(\.isAnalyzer).map(\.id))
        )
    }

    static func applyEnableRules(
        config: inout YAMLConfigurationEngine.YAMLConfig,
        ruleIds: [String],
        optInRuleIds: Set<String>,
        analyzerRuleIds: Set<String> = []
    ) {
        for ruleId in ruleIds {
            if config.rules[ruleId] == nil {
                config.rules[ruleId] = RuleConfiguration(enabled: true)
            } else {
                if var ruleConfig = config.rules[ruleId] {
                    ruleConfig.enabled = true
                    config.rules[ruleId] = ruleConfig
                }
            }

            if var disabledRules = config.disabledRules {
                disabledRules.removeAll { $0 == ruleId }
                config.disabledRules = disabledRules.isEmpty ? nil : disabledRules
            }

            if analyzerRuleIds.contains(ruleId) {
                var analyzerRules = config.analyzerRules ?? []
                if !analyzerRules.contains(ruleId) {
                    analyzerRules.append(ruleId)
                    config.analyzerRules = analyzerRules
                }
            } else if optInRuleIds.contains(ruleId) {
                var optInRules = config.optInRules ?? []
                if !optInRules.contains(ruleId) {
                    optInRules.append(ruleId)
                    config.optInRules = optInRules
                }
            }

            if var onlyRules = config.onlyRules {
                if !onlyRules.contains(ruleId) {
                    onlyRules.append(ruleId)
                    config.onlyRules = onlyRules
                }
            }
        }
    }

    /// Returns `entries` with every entry named in `ruleIds` flipped to enabled,
    /// preserving order and each entry's existing impact result.
    static func markEntriesEnabled(
        in entries: [RuleAuditEntry],
        ruleIds: Set<String>
    ) -> [RuleAuditEntry] {
        entries.map { entry in
            guard ruleIds.contains(entry.id) else { return entry }
            return RuleAuditEntry(
                rule: entry.rule,
                impactResult: entry.impactResult,
                isCurrentlyEnabled: true
            )
        }
    }

    static func postRuleChangeNotification(ruleIds: [String]) {
        NotificationCenter.default.post(
            name: .ruleConfigurationDidChange,
            object: nil,
            userInfo: ["ruleIds": ruleIds]
        )
    }
}
