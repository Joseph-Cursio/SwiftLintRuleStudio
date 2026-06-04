//
//  ConfigMapView.swift
//  SwiftLintRuleStudio
//
//  The Config Map: a sparse tree of the workspace's nested .swiftlint.yml files
//  on the left, and the effective resolved config (with per-rule "set by"
//  attribution) for the selected folder on the right.
//

import SwiftLintRuleStudioCore
import SwiftUI

struct ConfigMapView: View {
    @State private var viewModel: ConfigMapViewModel

    init(workspacePath: URL?) {
        _viewModel = State(initialValue: ConfigMapViewModel(workspacePath: workspacePath))
    }

    // Test seam: inject a pre-built view model.
    init(viewModel: ConfigMapViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .navigationTitle("Config Map")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: viewModel.load) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("ConfigMapRefreshButton")
                }
            }
            .onAppear { viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasWorkspace {
            ContentUnavailableView(
                "No Workspace",
                systemImage: "folder.badge.questionmark",
                description: Text("Open a project to map its SwiftLint configs.")
            )
        } else if viewModel.treeRows.isEmpty && !viewModel.isLoading {
            ContentUnavailableView(
                "No SwiftLint Configs",
                systemImage: "doc.text.magnifyingglass",
                description: Text("This project has no .swiftlint.yml files.")
            )
        } else {
            HSplitView {
                treeList
                    .frame(minWidth: 240, idealWidth: 300)
                inspector
                    .frame(minWidth: 320, idealWidth: 480)
            }
        }
    }

    private var treeList: some View {
        List(viewModel.treeRows, selection: Bindable(viewModel).selectedRowID) { row in
            ConfigTreeRowView(row: row)
        }
        .onChange(of: viewModel.selectedRowID) { _, newValue in
            if let newValue = newValue {
                viewModel.select(rowID: newValue)
            }
        }
        .accessibilityIdentifier("ConfigMapTreeList")
    }

    @ViewBuilder
    private var inspector: some View {
        if let display = viewModel.resolvedDisplay {
            ResolvedConfigInspectorView(display: display)
        } else {
            Text("Select a config to inspect")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
