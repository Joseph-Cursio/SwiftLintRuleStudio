//
//  RuleAuditView+Actions.swift
//  SwiftLintRuleStudio
//
//  Actions for the Rule Audit view: audit execution, enable rules, file counting
//

import SwiftLintRuleStudioCore
import SwiftUI

// MARK: - Audit Execution

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

    func runAudit() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else {
            return
        }

        isAuditing = true
        auditEntries = []
        selectedRules.removeAll()
        expandedRuleId = nil

        Task {
            await executeAudit(for: workspace)
        }
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
        guard let workspace = dependencies.workspaceManager.currentWorkspace,
              let configPath = workspace.configPath else {
            return
        }

        isEnabling = true

        Task {
            do {
                let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
                try yamlEngine.load()
                var config = yamlEngine.getConfig()
                let optInRuleIds = Set(
                    dependencies.ruleRegistry.rules
                        .filter { $0.isOptIn && !$0.isAnalyzer }
                        .map(\.id)
                )
                let analyzerRuleIds = Set(
                    dependencies.ruleRegistry.rules
                        .filter(\.isAnalyzer)
                        .map(\.id)
                )

                Self.applyEnableRules(
                    config: &config,
                    ruleIds: Array(selectedRules),
                    optInRuleIds: optInRuleIds,
                    analyzerRuleIds: analyzerRuleIds
                )

                try yamlEngine.save(config: config, createBackup: true)
                Self.postRuleChangeNotification(ruleIds: Array(selectedRules))

                // Update entries to reflect newly enabled rules
                auditEntries = Self.markEntriesEnabled(in: auditEntries, ruleIds: selectedRules)

                selectedRules.removeAll()
                isEnabling = false
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                isEnabling = false
            }
        }
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
}

// MARK: - Helpers

extension RuleAuditView {
    func executeAudit(for workspace: Workspace) async {
        do {
            var allRules = dependencies.ruleRegistry.rules
            if allRules.isEmpty {
                allRules = try await dependencies.ruleRegistry.loadRules()
            }
            let optInRuleIds = Set(allRules.filter { $0.isOptIn && !$0.isAnalyzer }.map(\.id))
            let analyzerRuleIds = Set(allRules.filter(\.isAnalyzer).map(\.id))

            let config = Self.loadConfiguration(for: workspace)
            let disabledRules = allRules.filter { !Self.isRuleEnabled($0, config: config) }
            let enabledRules = allRules.filter { Self.isRuleEnabled($0, config: config) }
            let disabledRuleIds = disabledRules.map(\.id)

            // Count Swift files in workspace
            let swiftFileCount = Self.countSwiftFiles(in: workspace)

            guard !disabledRuleIds.isEmpty else {
                finishAudit(
                    disabledResults: [],
                    enabledRules: enabledRules,
                    allRules: allRules,
                    swiftFileCount: swiftFileCount,
                    duration: 0
                )
                return
            }

            let batchResult = try await dependencies.impactSimulator.simulateRules(
                ruleIds: disabledRuleIds,
                workspace: workspace,
                baseConfigPath: workspace.configPath,
                classification: RuleClassification(
                    optInRuleIds: optInRuleIds,
                    analyzerRuleIds: analyzerRuleIds
                )
            ) { current, total, ruleId in
                auditProgress = AuditProgress(current: current, total: total, ruleId: ruleId)
            }

            finishAudit(
                disabledResults: batchResult.results,
                enabledRules: enabledRules,
                allRules: allRules,
                swiftFileCount: swiftFileCount,
                duration: batchResult.totalDuration
            )
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isAuditing = false
            auditProgress = nil
        }
    }

    func finishAudit(
        disabledResults: [RuleImpactResult],
        enabledRules: [Rule],
        allRules: [Rule],
        swiftFileCount: Int,
        duration: TimeInterval
    ) {
        auditEntries = Self.buildAuditEntries(
            disabledResults: disabledResults,
            enabledRules: enabledRules,
            allRules: allRules
        )
        totalSwiftFiles = swiftFileCount
        auditDuration = duration
        isAuditing = false
        auditProgress = nil
    }

    /// Builds the audit's display rows: one tested entry per simulated disabled rule,
    /// plus a greyed-out entry per already-enabled rule, ordered disabled-first and
    /// then by ascending violation count. Results naming a rule absent from
    /// `allRules` are dropped.
    static func buildAuditEntries(
        disabledResults: [RuleImpactResult],
        enabledRules: [Rule],
        allRules: [Rule]
    ) -> [RuleAuditEntry] {
        let ruleMap = Dictionary(allRules.map { ($0.id, $0) }) { first, _ in first }

        // Build entries for disabled rules (tested)
        var entries: [RuleAuditEntry] = disabledResults.compactMap { result in
            guard let rule = ruleMap[result.ruleId] else { return nil }
            return RuleAuditEntry(
                rule: rule,
                impactResult: result,
                isCurrentlyEnabled: false
            )
        }

        // Add entries for enabled rules (greyed out, not tested)
        let enabledEntries = enabledRules.map { rule in
            RuleAuditEntry(
                rule: rule,
                impactResult: nil,
                isCurrentlyEnabled: true
            )
        }
        entries.append(contentsOf: enabledEntries)

        // Sort: safe first, then by violation count ascending
        entries.sort { lhs, rhs in
            if lhs.isCurrentlyEnabled != rhs.isCurrentlyEnabled {
                return !lhs.isCurrentlyEnabled
            }
            return lhs.violationCount < rhs.violationCount
        }

        return entries
    }

    static func countSwiftFiles(in workspace: Workspace) -> Int {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: workspace.path,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0

        while let url = enumerator.nextObject() as? URL {
            let path = url.path
            if DefaultExclusions.pathPatterns.contains(where: { path.contains($0) }) {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "swift" {
                count += 1
            }
        }
        return count
    }

    static func postRuleChangeNotification(ruleIds: [String]) {
        NotificationCenter.default.post(
            name: .ruleConfigurationDidChange,
            object: nil,
            userInfo: ["ruleIds": ruleIds]
        )
    }

    static func loadConfiguration(for workspace: Workspace) -> YAMLConfigurationEngine.YAMLConfig {
        let configPath = workspace.configPath
            ?? workspace.path.appendingPathComponent(".swiftlint.yml")
        let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
        do {
            try yamlEngine.load()
            return yamlEngine.getConfig()
        } catch {
            return YAMLConfigurationEngine.YAMLConfig()
        }
    }

}

extension RuleAuditView {
    static func isRuleEnabled(_ rule: Rule, config: YAMLConfigurationEngine.YAMLConfig) -> Bool {
        if let onlyRules = config.onlyRules {
            return onlyRules.contains(rule.id)
        }
        if rule.isAnalyzer {
            if let ruleConfig = config.rules[rule.id], ruleConfig.enabled == false {
                return false
            }
            return config.analyzerRules?.contains(rule.id) ?? false
        }
        if rule.isOptIn {
            if let ruleConfig = config.rules[rule.id], ruleConfig.enabled == false {
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
}
