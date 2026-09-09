//
//  BulkOperationToolbar.swift
//  SwiftLintRuleStudio
//
//  Toolbar shown during multi-select mode for batch rule operations
//

import SwiftLintRuleStudioCore
import SwiftUI

/// How many rules the bulk toolbar is acting on.
///
/// Takes the count. `BulkOperationToolbar` is handed five closures, every one of them freshly
/// allocated on each update of the browser above it, so the toolbar value never compares equal and
/// its whole body re-runs — including this label, whose text changes only when the count does.
private struct BulkSelectionLabel: View {
    let count: Int

    var body: some View {
        Text("\(count) selected")
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
    }
}

struct BulkOperationToolbar: View {
    let selectedCount: Int
    let onEnableAll: () -> Void
    let onDisableAll: () -> Void
    let onSetSeverity: (Severity) -> Void
    let onPreview: () -> Void
    let onClearSelection: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                BulkSelectionLabel(count: selectedCount)
                Divider().frame(height: 20)
                enableDisableButtons
                Divider().frame(height: 20)
                severityMenu
                Spacer()
                trailingActions
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    @ViewBuilder
    private var enableDisableButtons: some View {
        Button("Enable All") {
            onEnableAll()
        }
        .buttonStyle(.bordered)
        .disabled(selectedCount == 0)
        .accessibilityIdentifier("BulkOperationEnableAllButton")

        Button("Disable All") {
            onDisableAll()
        }
        .buttonStyle(.bordered)
        .disabled(selectedCount == 0)
        .accessibilityIdentifier("BulkOperationDisableAllButton")
    }

    private var severityMenu: some View {
        Menu {
            ForEach(Severity.allCases) { severity in
                Button(severity.displayName) {
                    onSetSeverity(severity)
                }
            }
        } label: {
            Label("Set Severity", systemImage: "exclamationmark.triangle")
        }
        .disabled(selectedCount == 0)
    }

    @ViewBuilder
    private var trailingActions: some View {
        Button("Preview Changes") {
            onPreview()
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedCount == 0)
        .accessibilityIdentifier("BulkOperationPreviewChangesButton")

        Button {
            onClearSelection()
        } label: {
            Label("Clear", systemImage: "xmark.circle")
        }
        .buttonStyle(.bordered)
    }
}

#Preview {
    BulkOperationToolbar(
        selectedCount: 3,
        onEnableAll: {},
        onDisableAll: {},
        onSetSeverity: { _ in },
        onPreview: {},
        onClearSelection: {}
    )
    .padding()
}
