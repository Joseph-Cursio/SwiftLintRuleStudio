//
//  SafeRulesDiscoveryView+Actions.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI

private struct RuleDiscoveryContext {
    let optInRuleIds: Set<String>
    let disabledRuleIds: [String]
    let config: YAMLConfigurationEngine.YAMLConfig
    let allRules: [Rule]
}

extension SafeRulesDiscoveryView {
    func discoverSafeRules() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else {
            return
        }

        isDiscovering = true
        safeRules = []
        selectedRules.removeAll()

        Task {
            await runSafeRuleDiscovery(for: workspace)
        }
    }

    func toggleSelection(for ruleId: String) {
        if selectedRules.contains(ruleId) {
            selectedRules.remove(ruleId)
        } else {
            selectedRules.insert(ruleId)
        }
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
                let optInRuleIds = Set(dependencies.ruleRegistry.rules.filter { $0.isOptIn }.map { $0.id })
                Self.applyEnableRules(
                    config: &config,
                    ruleIds: Array(selectedRules),
                    optInRuleIds: optInRuleIds
                )

                try yamlEngine.save(config: config, createBackup: true)
                postRuleChangeNotification(ruleIds: Array(selectedRules))

                isEnabling = false
                dismiss()
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

private extension SafeRulesDiscoveryView {
    func runSafeRuleDiscovery(for workspace: Workspace) async {
        do {
            let context = try await buildDiscoveryContext(for: workspace)
            guard !context.disabledRuleIds.isEmpty else {
                await finishDiscovery(with: [], selectedRuleIds: [])
                return
            }

            let safeRuleIds = try await findSafeRuleIds(
                workspace: workspace,
                disabledRuleIds: context.disabledRuleIds,
                optInRuleIds: context.optInRuleIds
            )
            let results = try await loadImpactResults(
                ruleIds: safeRuleIds,
                workspace: workspace,
                optInRuleIds: context.optInRuleIds
            )

            await finishDiscovery(with: results, selectedRuleIds: safeRuleIds)
        } catch {
            await failDiscovery(with: error)
        }
    }

    func buildDiscoveryContext(for workspace: Workspace) async throws -> RuleDiscoveryContext {
        var allRules = dependencies.ruleRegistry.rules
        if allRules.isEmpty {
            allRules = try await dependencies.ruleRegistry.loadRules()
        }
        let optInRuleIds = Set(allRules.filter { $0.isOptIn }.map { $0.id })
        let config = loadConfiguration(for: workspace)
        let disabledRuleIds = allRules
            .filter { !isRuleEnabled($0, config: config) }
            .map { $0.id }

        return RuleDiscoveryContext(
            optInRuleIds: optInRuleIds,
            disabledRuleIds: disabledRuleIds,
            config: config,
            allRules: allRules
        )
    }

    func findSafeRuleIds(
        workspace: Workspace,
        disabledRuleIds: [String],
        optInRuleIds: Set<String>
    ) async throws -> [String] {
        try await dependencies.impactSimulator.findSafeRules(
            workspace: workspace,
            baseConfigPath: workspace.configPath,
            disabledRuleIds: disabledRuleIds,
            optInRuleIds: optInRuleIds
        ) { current, total, ruleId in
            discoveryProgress = DiscoveryProgress(current: current, total: total, ruleId: ruleId)
        }
    }

    func loadImpactResults(
        ruleIds: [String],
        workspace: Workspace,
        optInRuleIds: Set<String>
    ) async throws -> [RuleImpactResult] {
        var results: [RuleImpactResult] = []
        for ruleId in ruleIds {
            let isOptIn = optInRuleIds.contains(ruleId)
            let result = try await dependencies.impactSimulator.simulateRule(
                ruleId: ruleId,
                workspace: workspace,
                baseConfigPath: workspace.configPath,
                isOptIn: isOptIn
            )
            results.append(result)
        }
        return results
    }

    func finishDiscovery(with results: [RuleImpactResult], selectedRuleIds: [String]) async {
        safeRules = results
        selectedRules = Set(selectedRuleIds)
        isDiscovering = false
        discoveryProgress = nil
    }

    func failDiscovery(with error: Error) async {
        errorMessage = error.localizedDescription
        showError = true
        isDiscovering = false
        discoveryProgress = nil
    }

    func postRuleChangeNotification(ruleIds: [String]) {
        NotificationCenter.default.post(
            name: .ruleConfigurationDidChange,
            object: nil,
            userInfo: ["ruleIds": ruleIds]
        )
    }

    func loadConfiguration(for workspace: Workspace) -> YAMLConfigurationEngine.YAMLConfig {
        let configPath = workspace.configPath ?? workspace.path.appendingPathComponent(".swiftlint.yml")
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
