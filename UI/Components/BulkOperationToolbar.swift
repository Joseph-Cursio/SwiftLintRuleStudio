//
//  BulkOperationToolbar.swift
//  SwiftLintRuleStudio
//
//  Toolbar shown during multi-select mode for batch rule operations
//

import SwiftUI
import SwiftLintRuleStudioCore

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
                selectionLabel
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

    private var selectionLabel: some View {
        Text("\(selectedCount) selected")
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
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
