//
//  ConfigVersionHistoryView.swift
//  SwiftLintRuleStudio
//
//  Timeline view for browsing and restoring configuration version history
//

import SwiftUI

struct ConfigVersionHistoryView: View {
    @EnvironmentObject var dependencies: DependencyContainer
    @StateObject private var viewModel: ConfigVersionHistoryViewModel

    init(service: ConfigVersionHistoryServiceProtocol, configPath: URL?) {
        _viewModel = StateObject(wrappedValue: ConfigVersionHistoryViewModel(
            service: service,
            configPath: configPath
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.backups.isEmpty && !viewModel.isLoading {
                emptyStateView
            } else {
                HSplitView {
                    backupListView
                        .frame(minWidth: 250, idealWidth: 300)

                    diffDetailView
                        .frame(minWidth: 300, idealWidth: 500)
                }
            }
        }
        .navigationTitle("Version History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.loadBackups()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("ConfigHistoryRefreshButton")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Keep Last 5") { viewModel.pruneOld(keepCount: 5) }
                    Button("Keep Last 10") { viewModel.pruneOld(keepCount: 10) }
                    Button("Keep Last 20") { viewModel.pruneOld(keepCount: 20) }
                } label: {
                    Label("Prune", systemImage: "trash")
                }
                .accessibilityIdentifier("ConfigHistoryPruneMenu")
            }
        }
        .onAppear {
            viewModel.loadBackups()
        }
        .alert("Restore Configuration?", isPresented: $viewModel.showRestoreConfirmation) {
            Button("Restore", role: .destructive) {
                viewModel.restoreVersion()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let backup = viewModel.backupToRestore {
                Text(
                    "This will restore the configuration from \(backup.formattedDate)." +
                    " A safety backup of the current configuration will be created first."
                )
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error?.localizedDescription ?? "An unknown error occurred.")
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Version History")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Configuration backups will appear here after you save changes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var backupListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Backups (\(viewModel.backups.count))")
                    .font(.headline)
                Spacer()
                if viewModel.selectedBackup != nil || viewModel.comparisonBackup != nil {
                    Button("Clear") {
                        viewModel.clearComparison()
                    }
                    .font(.caption)
                }
            }
            .padding()

            Divider()

            List {
                ForEach(viewModel.backups) { backup in
                    BackupRow(
                        backup: backup,
                        isSelected: viewModel.selectedBackup?.id == backup.id,
                        isComparison: viewModel.comparisonBackup?.id == backup.id,
                        onSelect: { viewModel.selectForComparison(backup) },
                        onRestore: { viewModel.confirmRestore(backup) }
                    )
                }
            }
            .listStyle(.sidebar)

            if viewModel.selectedBackup != nil && viewModel.comparisonBackup == nil {
                Text("Select another backup to compare")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private var diffDetailView: some View {
        VStack {
            if let diff = viewModel.currentDiff {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if let first = viewModel.selectedBackup {
                            Label(first.formattedDate, systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        if let second = viewModel.comparisonBackup {
                            Label(second.formattedDate, systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    ConfigDiffPreviewView(
                        diff: diff,
                        ruleName: "Version Comparison"
                    ) {
                        // Save = restore the comparison backup
                        if let backup = viewModel.comparisonBackup {
                            viewModel.confirmRestore(backup)
                        }
                    } onCancel: {
                        viewModel.clearComparison()
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text("Select two backups to compare")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Backup Row

struct BackupRow: View {
    let backup: ConfigBackup
    let isSelected: Bool
    let isComparison: Bool
    let onSelect: () -> Void
    let onRestore: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(backup.formattedDate)
                    .font(.body)
                    .fontWeight(isSelected || isComparison ? .semibold : .regular)

                Text(backup.formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "1.circle.fill")
                    .foregroundStyle(.blue)
                    .accessibilityLabel("First selection")
            } else if isComparison {
                Image(systemName: "2.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Second selection")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button {
                onRestore()
            } label: {
                Label("Restore This Version", systemImage: "arrow.uturn.backward")
            }
        }
        .padding(.vertical, 2)
        .background(
            (isSelected || isComparison) ? Color.accentColor.opacity(0.1) : Color.clear
        )
        .clipShape(.rect(cornerRadius: 4))
    }
}
