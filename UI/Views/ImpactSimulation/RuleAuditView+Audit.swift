//
//  RuleAuditView+Audit.swift
//  SwiftLintRuleStudio
//
//  Running the audit: simulating the disabled rules against the workspace and
//  turning the results into the view's rows.
//

import SwiftLintRuleStudioCore
import SwiftUI

// MARK: - Running an Audit

extension RuleAuditView {
    func runAudit() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else {
            return
        }

        isAuditing = true
        auditEntries = []
        selectedRules.removeAll()
        expandedRuleId = nil

        // One audit at a time: a second run supersedes the first rather than racing it, and
        // only the current run reports back — see `RuleAuditRunner`.
        auditRunner.start(
            for: workspace,
            currentWorkspace: { dependencies.workspaceManager.currentWorkspace },
            audit: { onProgress in try await auditOutcome(for: workspace, onProgress: onProgress) },
            onProgress: { auditProgress = $0 },
            onFinish: { result in
                switch result {
                case .success(let outcome):
                    applyAuditOutcome(outcome)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showError = true
                    isAuditing = false
                    auditProgress = nil
                }
            }
        )
    }

    /// Audits the registry's rules against `workspace` with this edition's simulator.
    private func auditOutcome(
        for workspace: Workspace,
        onProgress: @escaping (AuditProgress) -> Void
    ) async throws -> AuditOutcome {
        var allRules = dependencies.ruleRegistry.rules
        if allRules.isEmpty {
            allRules = try await dependencies.ruleRegistry.loadRules()
        }
        return try await Self.performAudit(
            workspace: workspace,
            rules: allRules,
            simulator: dependencies.impactSimulator,
            capabilities: capabilities,
            onProgress: onProgress
        )
    }

    func applyAuditOutcome(_ outcome: AuditOutcome) {
        auditEntries = outcome.entries
        totalSwiftFiles = outcome.swiftFileCount
        auditDuration = outcome.duration
        isAuditing = false
        auditProgress = nil
    }

    /// Everything an audit run produces, before it is written back to view state.
    struct AuditOutcome {
        let entries: [RuleAuditEntry]
        let swiftFileCount: Int
        let duration: TimeInterval
    }

    /// Audits `rules` against `workspace` using `simulator`, reporting progress
    /// as each rule is tested. Rules the configuration already enables are
    /// reported without being simulated; when none are disabled the simulator is
    /// not invoked at all.
    ///
    /// `capabilities` has no default: it decides which rules this edition can
    /// measure, and a forgotten one would call every SourceKit rule in the
    /// sandboxed edition safe to enable.
    static func performAudit(
        workspace: Workspace,
        rules: [Rule],
        simulator: any ImpactSimulatorProtocol,
        capabilities: Set<AppCapability>,
        onProgress: @escaping (AuditProgress) -> Void
    ) async throws -> AuditOutcome {
        let config = loadConfiguration(for: workspace)
        let (enabledRules, disabledRules) = partitionRules(rules, config: config)
        let swiftFileCount = countSwiftFiles(in: workspace)
        let disabledRuleIds = disabledRules.map(\.id)

        guard !disabledRuleIds.isEmpty else {
            return AuditOutcome(
                entries: buildAuditEntries(
                    disabledResults: [],
                    enabledRules: enabledRules,
                    allRules: rules
                ),
                swiftFileCount: swiftFileCount,
                duration: 0
            )
        }

        let batchResult = try await simulator.simulateRules(
            ruleIds: disabledRuleIds,
            workspace: workspace,
            baseConfigPath: workspace.configPath,
            classification: simulationClassification(of: rules, capabilities: capabilities)
        ) { current, total, ruleId in
            onProgress(AuditProgress(current: current, total: total, ruleId: ruleId))
        }

        return AuditOutcome(
            entries: buildAuditEntries(
                disabledResults: batchResult.results,
                enabledRules: enabledRules,
                allRules: rules
            ),
            swiftFileCount: swiftFileCount,
            duration: batchResult.totalDuration
        )
    }

    /// The enable path's classification, plus the rules this edition can't lint: a
    /// SourceKit rule lints clean where SourceKit can't load, whatever the code holds,
    /// so the simulator reports it as unmeasurable instead of as a "safe" zero.
    static func simulationClassification(
        of rules: [Rule],
        capabilities: Set<AppCapability>
    ) -> RuleClassification {
        var classification = ruleClassification(from: rules)
        classification.sourceKitUnavailableRuleIds = Set(
            rules.filter { $0.isUnavailableForLinting(capabilities: capabilities) }.map(\.id)
        )
        return classification
    }

    /// Partitions `rules` by whether `config` currently switches them on.
    static func partitionRules(
        _ rules: [Rule],
        config: YAMLConfigurationEngine.YAMLConfig
    ) -> (enabled: [Rule], disabled: [Rule]) {
        var enabled: [Rule] = []
        var disabled: [Rule] = []
        for rule in rules {
            if isRuleEnabled(rule, config: config) {
                enabled.append(rule)
            } else {
                disabled.append(rule)
            }
        }
        return (enabled, disabled)
    }

    /// Builds the audit's display rows: one tested entry per simulated disabled rule,
    /// plus a greyed-out entry per already-enabled rule, ordered disabled-first and
    /// then by ascending violation count, with rules that have no count last. Results
    /// naming a rule absent from `allRules` are dropped.
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

        // Sort: disabled first, then by violation count ascending — safe rules on top, and
        // rules the audit couldn't measure below every rule it could.
        entries.sort { RuleAuditEntry.isOrderedByViolations($0, $1, ascending: true) }

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

    static func loadConfiguration(for workspace: Workspace) -> YAMLConfigurationEngine.YAMLConfig {
        let configPath = workspace.configPath
            ?? workspace.path.appendingPathComponent(".swiftlint.yml")
        do {
            return try YAMLConfigurationEngine.loadConfig(at: configPath)
        } catch {
            return YAMLConfigurationEngine.YAMLConfig()
        }
    }

    static func isRuleEnabled(_ rule: Rule, config: YAMLConfigurationEngine.YAMLConfig) -> Bool {
        RuleEnablementResolver.isRuleEnabled(rule, config: config)
    }
}
