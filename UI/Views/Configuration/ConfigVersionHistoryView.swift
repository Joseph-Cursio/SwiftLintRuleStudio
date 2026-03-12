//
//  ConfigVersionHistoryView.swift
//  SwiftLintRuleStudio
//
//  Timeline view for browsing and restoring configuration version history
//

import SwiftUI

struct ConfigVersionHistoryView: View {
    @State private var viewModel: ConfigVersionHistoryViewModel

    init(service: ConfigVersionHistoryServiceProtocol, configPath: URL?) {
        _viewModel = State(initialValue: ConfigVersionHistoryViewModel(
            service: service,
            configPath: configPath
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.backups.isEmpty && !viewModel.isLoading {
                ConfigVersionHistoryEmptyStateView()
            } else {
                HSplitView {
                    ConfigVersionHistoryBackupListView(viewModel: viewModel)
                        .frame(minWidth: 250, idealWidth: 300)

                    ConfigVersionHistoryDiffDetailView(viewModel: viewModel)
                        .frame(minWidth: 300, idealWidth: 500)
                }
            }
        }
        .navigationTitle("Version History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: viewModel.loadBackups) {
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
        .alert("Restore Configuration?", isPresented: Bindable(viewModel).showRestoreConfirmation) {
            Button("Restore", role: .destructive, action: viewModel.restoreVersion)
            Button("Cancel", role: .cancel) {}
        } message: {
            if let backup = viewModel.backupToRestore {
                Text(
                    "This will restore the configuration from \(backup.formattedDate)." +
                    " A safety backup of the current configuration will be created first."
                )
            }
        }
        .alert("Error", isPresented: Bindable(viewModel).showError) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error?.localizedDescription ?? "An unknown error occurred.")
        }
    }

}
