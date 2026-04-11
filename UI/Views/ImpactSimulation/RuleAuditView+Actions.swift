//
//  RuleAuditView+Actions.swift
//  SwiftLintRuleStudio
//
//  Actions for the Rule Audit view: audit execution, enable rules, file counting
//

import SwiftUI
import SwiftLintRuleStudioCore

// MARK: - Audit Execution

extension RuleAuditView {
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
        let safeRuleIds = auditEntries
            .filter { !$0.isCurrentlyEnabled && $0.effortCategory == .safe }
            .map(\.id)

        selectedRules = Set(safeRuleIds)
        enableSelectedRules()
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
                        .filter { $0.isOptIn }
                        .map { $0.id }
                )

                Self.applyEnableRules(
                    config: &config,
                    ruleIds: Array(selectedRules),
                    optInRuleIds: optInRuleIds
                )

                try yamlEngine.save(config: config, createBackup: true)
                postRuleChangeNotification(ruleIds: Array(selectedRules))

                // Update entries to reflect newly enabled rules
                let enabledIds = selectedRules
                auditEntries = auditEntries.map { entry in
                    if enabledIds.contains(entry.id) {
                        return RuleAuditEntry(
                            rule: entry.rule,
                            impactResult: entry.impactResult,
                            isCurrentlyEnabled: true
                        )
                    }
                    return entry
                }

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
        optInRuleIds: Set<String>
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

            if optInRuleIds.contains(ruleId) {
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
}

// MARK: - Private Helpers

private extension RuleAuditView {
    func executeAudit(for workspace: Workspace) async {
        do {
            var allRules = dependencies.ruleRegistry.rules
            if allRules.isEmpty {
                allRules = try await dependencies.ruleRegistry.loadRules()
            }
            let optInRuleIds = Set(allRules.filter { $0.isOptIn }.map { $0.id })

            let config = loadConfiguration(for: workspace)
            let disabledRules = allRules.filter { !isRuleEnabled($0, config: config) }
            let enabledRules = allRules.filter { isRuleEnabled($0, config: config) }
            let disabledRuleIds = disabledRules.map { $0.id }

            // Count Swift files in workspace
            let swiftFileCount = countSwiftFiles(in: workspace)

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
                optInRuleIds: optInRuleIds
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
        let ruleMap = Dictionary(uniqueKeysWithValues: allRules.map { ($0.id, $0) })

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

        auditEntries = entries
        totalSwiftFiles = swiftFileCount
        auditDuration = duration
        isAuditing = false
        auditProgress = nil
    }

    func countSwiftFiles(in workspace: Workspace) -> Int {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: workspace.path,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0
        let excludedDirs = [".build", "Pods", "DerivedData", "Carthage", ".swiftpm", "Build"]

        while let url = enumerator.nextObject() as? URL {
            let pathComponents = url.pathComponents
            if excludedDirs.contains(where: { pathComponents.contains($0) }) {
                continue
            }
            if url.pathExtension == "swift" {
                count += 1
            }
        }
        return count
    }

    func postRuleChangeNotification(ruleIds: [String]) {
        NotificationCenter.default.post(
            name: .ruleConfigurationDidChange,
            object: nil,
            userInfo: ["ruleIds": ruleIds]
        )
    }

    func loadConfiguration(for workspace: Workspace) -> YAMLConfigurationEngine.YAMLConfig {
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

    func isRuleEnabled(_ rule: Rule, config: YAMLConfigurationEngine.YAMLConfig) -> Bool {
        if let onlyRules = config.onlyRules {
            return onlyRules.contains(rule.id)
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
