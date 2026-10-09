//
//  DashboardViewModel.swift
//  SwiftLintRuleStudio
//

import Foundation
import SwiftLintRuleStudioCore

/// The counts across the top of the Dashboard.
struct DashboardStats: Equatable {
    let totalRules: Int
    /// Rules the workspace's configuration runs. Nil when `.swiftlint.yml` couldn't be read.
    let enabledRules: Int?
    let enabledOptInRules: Int?
    /// Open violations from the last analysis: neither suppressed nor resolved. Nil until
    /// the workspace has been analyzed, so an unanalyzed workspace doesn't look clean.
    let errors: Int?
    let warnings: Int?
}

/// Loads what the Dashboard shows for the open workspace: rule and violation counts,
/// and the configuration health report.
@MainActor
@Observable
final class DashboardViewModel {
    private(set) var stats: DashboardStats?
    private(set) var report: ConfigHealthReport?
    /// False when the workspace has no `.swiftlint.yml`; the counts and report then
    /// describe an empty configuration, which is what SwiftLint's defaults amount to.
    private(set) var hasConfigFile = false
    private(set) var errorMessage: String?

    private let analyzer: ConfigurationHealthAnalyzerProtocol
    private let violationStorage: ViolationStorageProtocol
    private let workspaceAnalyzer: any WorkspaceAnalyzerProtocol
    private let makeConfigEngine: (URL) -> any YAMLConfigurationEngineProtocol

    init(
        analyzer: ConfigurationHealthAnalyzerProtocol,
        violationStorage: ViolationStorageProtocol,
        workspaceAnalyzer: any WorkspaceAnalyzerProtocol,
        makeConfigEngine: @escaping (URL) -> any YAMLConfigurationEngineProtocol
    ) {
        self.analyzer = analyzer
        self.violationStorage = violationStorage
        self.workspaceAnalyzer = workspaceAnalyzer
        self.makeConfigEngine = makeConfigEngine
    }

    func load(rules: [Rule], workspace: Workspace) async {
        var problems: [String] = []

        // Which rules run is decided by the workspace's config, not the registry's
        // `isEnabled` flags, which only track the config the Rules browser last synced.
        let config = loadConfig(for: workspace, problems: &problems)
        let enabled = config.map { config in
            rules.filter { RuleEnablementResolver.isRuleEnabled($0, config: config) }
        }

        let open = await openViolations(in: workspace, problems: &problems)

        stats = DashboardStats(
            totalRules: rules.count,
            enabledRules: enabled?.count,
            enabledOptInRules: enabled?.filter(\.isOptIn).count,
            errors: open?.filter { $0.severity == .error }.count,
            warnings: open?.filter { $0.severity == .warning }.count
        )
        report = config.map { analyzer.analyze(config: $0, knownRules: rules) }
        errorMessage = problems.isEmpty ? nil : problems.joined(separator: "\n")
    }

    /// The workspace's configuration: an empty one when there's no `.swiftlint.yml`, nil
    /// when there is one that can't be read.
    private func loadConfig(
        for workspace: Workspace,
        problems: inout [String]
    ) -> YAMLConfigurationEngine.YAMLConfig? {
        guard let configPath = workspace.configPath,
              FileManager.default.fileExists(atPath: configPath.path) else {
            hasConfigFile = false
            return YAMLConfigurationEngine.YAMLConfig()
        }
        hasConfigFile = true
        let engine = makeConfigEngine(configPath)
        do {
            try engine.load()
            return engine.getConfig()
        } catch {
            problems.append("Couldn't read .swiftlint.yml: \(error.localizedDescription)")
            return nil
        }
    }

    /// The workspace's open violations, or nil when it hasn't been analyzed or they
    /// couldn't be loaded.
    private func openViolations(in workspace: Workspace, problems: inout [String]) async -> [Violation]? {
        let stored: [Violation]
        do {
            stored = try await violationStorage.fetchViolations(filter: .all, workspaceId: workspace.id)
        } catch {
            problems.append("Couldn't load violations: \(error.localizedDescription)")
            return nil
        }
        // The analyzer only remembers this launch; stored violations show an earlier one.
        guard workspaceAnalyzer.hasAnalyzed(workspaceID: workspace.id) || !stored.isEmpty else {
            return nil
        }
        return stored.filter { !$0.suppressed && $0.resolvedAt == nil }
    }
}
