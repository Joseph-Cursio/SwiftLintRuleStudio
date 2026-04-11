//
//  ViolationInspectorView.swift
//  SwiftLintRuleStudio
//
//  Main view for inspecting violations
//

import SwiftUI
import UniformTypeIdentifiers
import SwiftLintRuleStudioCore

struct ViolationInspectorView: View {
    @ScaledMetric(relativeTo: .title) var iconSizeMedium: CGFloat = 48

    @Environment(\.dependencies) var dependencies: DependencyContainer
    @State var viewModel: ViolationInspectorViewModel

    init() {
        // Create temporary storage for initialization
        // Will be updated in onAppear with actual storage from dependencies
        // Use do-catch to handle initialization errors gracefully
        let tempStorage: ViolationStorageActor
        do {
            tempStorage = try ViolationStorageActor(useInMemory: true)
        } catch {
            // If initialization fails, log the error and create a fallback
            // This prevents crashes and allows the view to still render
            // Try to create a file-based storage as fallback
            if let fallbackStorage = try? ViolationStorageActor(useInMemory: false) {
                tempStorage = fallbackStorage
            } else {
                // Last resort: create in-memory storage again (should work after fix)
                // This will crash if there's a fundamental issue, but that's better than silent failure
                fatalError(
                    "Failed to initialize ViolationStorageActor: \(error). " +
                        "This indicates a critical database configuration issue."
                )
            }
        }
        _viewModel = State(initialValue: ViolationInspectorViewModel(violationStorage: tempStorage))
    }

#if DEBUG
    init(viewModel: ViolationInspectorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }
#endif

    var body: some View {
        HSplitView {
            violationListView
                .frame(minWidth: 450, idealWidth: 500, maxWidth: 800)
            detailPanel
        }
        .navigationTitle("Enabled Rule Violations")
        .onAppear(perform: handleAppear)
        .onChange(of: dependencies.workspaceManager.currentWorkspace, handleWorkspaceChange)
        .onChange(of: dependencies.workspaceManager.configFileMissing, handleConfigMissingChange)
        .onReceive(NotificationCenter.default.publisher(for: .violationInspectorRefreshRequested)) { _ in
            Task { try? await viewModel.refreshViolations() }
        }
        .toolbar { toolbarContent }
    }

    private var detailPanel: some View {
        Group {
            if let selectedViolationId = viewModel.selectedViolationId,
               let violation = viewModel.filteredViolations.first(where: { $0.id == selectedViolationId }) {
                ViolationDetailView(
                    violation: violation,
                    onSuppress: { reason in
                        Task { try? await viewModel.suppressSelectedViolations(reason: reason) }
                    },
                    onResolve: {
                        Task { try? await viewModel.resolveSelectedViolations() }
                    }
                )
            } else {
                emptyDetailView
            }
        }
        .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private func handleAppear() {
        viewModel.violationStorage = dependencies.violationStorage
        viewModel.workspaceAnalyzer = dependencies.workspaceAnalyzer
        if let workspace = dependencies.workspaceManager.currentWorkspace {
            Task {
                try? await viewModel.loadViolations(for: workspace.id, workspace: workspace)
            }
        }
    }

    private func handleWorkspaceChange(_ oldWorkspace: Workspace?, _ newWorkspace: Workspace?) {
        if let workspace = newWorkspace {
            Task {
                try? await viewModel.loadViolations(for: workspace.id, workspace: workspace)
            }
        } else {
            Task { viewModel.clearViolations() }
        }
    }

    private func handleConfigMissingChange(_ wasMissing: Bool, _ isMissing: Bool) {
        guard !isMissing, dependencies.workspaceManager.currentWorkspace != nil else { return }
        Task {
            try? await viewModel.refreshViolations()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            refreshButton
            exportMenu
            navigationButtons
            selectionMenu
            actionsMenu
        }
    }

    private var refreshButton: some View {
        Button {
            Task { try? await viewModel.refreshViolations() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .accessibilityIdentifier("ViolationInspectorRefreshButton")
    }

    private var exportMenu: some View {
        Menu {
            SwiftUI.Section("Filtered") {
                Button("Export Filtered as JSON") { exportViolations(scope: .filtered, format: .json) }
                Button("Export Filtered as CSV") { exportViolations(scope: .filtered, format: .csv) }
            }
            SwiftUI.Section("Selected") {
                Button("Export Selected as JSON") { exportViolations(scope: .selected, format: .json) }
                    .disabled(viewModel.selectedViolationIds.isEmpty)
                Button("Export Selected as CSV") { exportViolations(scope: .selected, format: .csv) }
                    .disabled(viewModel.selectedViolationIds.isEmpty)
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
    }

    private var navigationButtons: some View {
        Group {
            Button { viewModel.selectNextViolation() } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .accessibilityIdentifier("ViolationInspectorNextButton")

            Button { viewModel.selectPreviousViolation() } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .accessibilityIdentifier("ViolationInspectorPreviousButton")
        }
    }

    private var selectionMenu: some View {
        Menu {
            Button("Select All") { viewModel.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
            Button("Clear Selection") { viewModel.deselectAll() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
        } label: {
            Label("Selection", systemImage: "checkmark.circle")
        }
        .disabled(viewModel.filteredViolations.isEmpty)
        .accessibilityIdentifier("ViolationInspectorSelectionMenu")
    }

    @ViewBuilder
    private var actionsMenu: some View {
        if !viewModel.selectedViolationIds.isEmpty {
            Menu {
                Button {
                    let suppressReason = "Suppressed via Violation Inspector"
                    Task { try? await viewModel.suppressSelectedViolations(reason: suppressReason) }
                } label: {
                    Label("Suppress Selected", systemImage: "eye.slash")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button {
                    Task { try? await viewModel.resolveSelectedViolations() }
                } label: {
                    Label("Mark as Resolved", systemImage: "checkmark.circle")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("ViolationInspectorActionsMenu")
        }
    }

}

enum ViolationExportScope: String {
    case filtered = "Filtered"
    case selected = "Selected"
}

enum ViolationExportFormat {
    case json
    case csv
}

// MARK: - Supporting Views

struct StatisticBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ViolationSummaryCard: View {
    let title: String
    let count: Int
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .tracking(0.5)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(count)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(color)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
        )
    }
}

struct ViolationGroupHeader: View {
    let title: String
    let count: Int
    let maxCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .lineLimit(1)

            Text("\(count)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(NSColor.separatorColor))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: barWidth(in: geometry.size.width), height: 6)
                }
                .frame(height: geometry.size.height)
            }
            .frame(width: 80, height: 14)
        }
    }

    private var barColor: Color {
        let ratio = maxCount > 0 ? Double(count) / Double(maxCount) : 0
        if ratio > 0.7 { return .red }
        if ratio > 0.3 { return .orange }
        return .yellow
    }

    private func barWidth(in totalWidth: CGFloat) -> CGFloat {
        guard maxCount > 0 else { return 0 }
        let proportion = CGFloat(count) / CGFloat(maxCount)
        return max(proportion * totalWidth, 3)
    }
}
