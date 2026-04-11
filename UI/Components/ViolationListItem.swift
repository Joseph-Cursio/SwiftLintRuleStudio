//
//  ViolationListItem.swift
//  SwiftLintRuleStudio
//
//  Component for displaying a violation in a list
//

import SwiftUI
import SwiftLintRuleStudioCore
import LintStudioUI

struct ViolationListItem: View {
    let violation: Violation
    var onOpenInXcode: (() -> Void)?

    @Environment(\.dependencies) var dependencies: DependencyContainer

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(severityColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                ruleHeaderRow
                Text(violation.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                fileLocationRow
            }

            Spacer()

            openInXcodeButton
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu { contextMenuItems }
    }

    @ViewBuilder
    private var ruleHeaderRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(violation.ruleID)
                .font(.headline)
                .lineLimit(1)
            SeverityBadge(severity: violation.severity)
            if violation.suppressed {
                Label("Suppressed", systemImage: "eye.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fileLocationRow: some View {
        HStack(spacing: 8) {
            Label(violation.filePath, systemImage: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\u{2022}")
                .foregroundStyle(.secondary)
            Label("Line \(violation.line)", systemImage: "number")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var openInXcodeButton: some View {
        if let onOpenInXcode = onOpenInXcode {
            Button {
                onOpenInXcode()
            } label: {
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Open in Xcode")
            }
            .buttonStyle(.plain)
            .help("Open in Xcode (\u{2318}O)")
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if let workspace = dependencies.workspaceManager.currentWorkspace {
            Button {
                Task {
                    await openInXcode(workspace: workspace)
                }
            } label: {
                Label("Open in Xcode", systemImage: "arrow.right.circle")
            }
            .keyboardShortcut("o", modifiers: .command)
        }
    }

    private func openInXcode(workspace: Workspace) {
        _ = try? dependencies.xcodeIntegrationService.openFile(
            at: violation.filePath,
            line: violation.line,
            column: violation.column,
            in: workspace
        )
    }

    private var severityColor: Color {
        switch violation.severity {
        case .error:
            return .red
        case .warning:
            return .orange
        }
    }
}
