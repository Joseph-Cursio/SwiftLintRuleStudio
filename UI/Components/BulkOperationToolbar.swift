//
//  BulkOperationToolbar.swift
//  SwiftLintRuleStudio
//
//  Toolbar shown during multi-select mode for batch rule operations
//

import SwiftUI

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
                Text("\(selectedCount) selected")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Divider()
                    .frame(height: 20)

                Button("Enable All") {
                    onEnableAll()
                }
                .buttonStyle(.bordered)
                .disabled(selectedCount == 0)

                Button("Disable All") {
                    onDisableAll()
                }
                .buttonStyle(.bordered)
                .disabled(selectedCount == 0)

                Divider()
                    .frame(height: 20)

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

                Spacer()

                Button("Preview Changes") {
                    onPreview()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCount == 0)

                Button {
                    onClearSelection()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }
}
