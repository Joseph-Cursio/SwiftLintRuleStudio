//
//  DashboardView.swift
//  SwiftLintRuleStudio
//
//  Summary of the open workspace: rule and violation counts above the
//  configuration health report.
//

import Combine
import SwiftLintRuleStudioCore
import SwiftUI

/// One count in the row across the top of the Dashboard.
private struct DashboardStatTile: View {
    let title: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

struct DashboardView: View {
    /// Shows a recommended preset's rules in the rule browser.
    let onReviewPreset: (RulePreset) -> Void

    @Environment(\.dependencies) private var dependencies
    @Environment(\.ruleRegistry) private var ruleRegistry
    @State private var viewModel: DashboardViewModel?

    /// Reload when the workspace changes, when rules finish loading, or when the workspace
    /// gains or loses its `.swiftlint.yml`. Edits to the config arrive by notification.
    private struct ReloadKey: Equatable {
        let workspaceID: UUID?
        let ruleCount: Int
        let configFileMissing: Bool
    }

    private var reloadKey: ReloadKey {
        ReloadKey(
            workspaceID: dependencies.workspaceManager.currentWorkspace?.id,
            ruleCount: ruleRegistry.rules.count,
            configFileMissing: dependencies.workspaceManager.configFileMissing
        )
    }

    /// Fires when an analysis finishes, wherever it was started from.
    private var analysisFinished: AnyPublisher<Bool, Never> {
        dependencies.workspaceAnalyzer.isAnalyzingPublisher
            .removeDuplicates()
            .dropFirst()
            .filter { !$0 }
            .eraseToAnyPublisher()
    }

    var body: some View {
        content
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Recalculate the dashboard")
                    .accessibilityIdentifier("DashboardRefreshButton")
                }
            }
            .task(id: reloadKey) { await reload() }
            .onReceive(NotificationCenter.default.publisher(for: .ruleConfigurationDidChange)) { _ in
                Task { await reload() }
            }
            .onReceive(analysisFinished) { _ in
                Task { await reload() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if dependencies.workspaceManager.currentWorkspace == nil {
            ContentUnavailableView {
                Label("No Workspace Open", systemImage: "chart.bar")
            } description: {
                Text("Open a workspace to see its rules, violations and configuration health.")
            }
        } else if ruleRegistry.rules.isEmpty || viewModel?.stats == nil {
            ProgressView("Loading\u{2026}")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let viewModel, let stats = viewModel.stats {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    statTiles(stats)
                    notes(for: viewModel)
                }
                .padding()

                Divider()

                if let report = viewModel.report {
                    ConfigHealthScoreView(report: report) { presetID in
                        if let preset = RulePresets.preset(for: presetID) {
                            onReviewPreset(preset)
                        }
                    }
                } else {
                    Spacer()
                }
            }
        }
    }

    private func statTiles(_ stats: DashboardStats) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            DashboardStatTile(
                title: "Rules enabled",
                value: stats.enabledRules.map { "\($0) of \(stats.totalRules)" } ?? Self.unknown
            )
            DashboardStatTile(title: "Opt-in rules enabled", value: Self.display(stats.enabledOptInRules))
            DashboardStatTile(
                title: "Errors",
                value: Self.display(stats.errors),
                tint: (stats.errors ?? 0) > 0 ? .red : .primary
            )
            DashboardStatTile(
                title: "Warnings",
                value: Self.display(stats.warnings),
                tint: (stats.warnings ?? 0) > 0 ? .orange : .primary
            )
        }
    }

    /// Shown in place of a count the Dashboard doesn't have.
    private static let unknown = "\u{2014}"

    private static func display(_ count: Int?) -> String {
        count.map(String.init) ?? unknown
    }

    @ViewBuilder
    private func notes(for viewModel: DashboardViewModel) -> some View {
        if viewModel.stats?.errors == nil {
            Label(
                "This workspace hasn't been analyzed yet. Open Violations to analyze it.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Text("Errors and warnings are open violations from the last analysis.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if !viewModel.hasConfigFile {
            Label(
                "This workspace has no .swiftlint.yml, so the health score reflects SwiftLint's defaults.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let errorMessage = viewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func reload() async {
        guard let workspace = dependencies.workspaceManager.currentWorkspace,
              !ruleRegistry.rules.isEmpty else { return }
        let model = viewModel ?? DashboardViewModel(
            analyzer: dependencies.configurationHealthAnalyzer,
            violationStorage: dependencies.violationStorage,
            workspaceAnalyzer: dependencies.workspaceAnalyzer
        ) { configPath in
            // The view model reads the config through the protocol; this is where the
            // production engine is chosen, the same way RuleDetailView does.
            // swiftprojectlint:disable:next direct-instantiation
            YAMLConfigurationEngine(configPath: configPath)
        }
        viewModel = model
        await model.load(rules: ruleRegistry.rules, workspace: workspace)
    }
}
