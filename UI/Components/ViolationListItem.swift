//
//  ViolationListItem.swift
//  SwiftLintRuleStudio
//
//  Component for displaying a violation in a list
//

import LintStudioUI
import SwiftLintRuleStudioCore
import SwiftUI

// MARK: - Row subviews

/// Rule id, severity and the suppressed marker.
///
/// Takes the three values it draws rather than the whole `Violation`, and none of the row's other
/// inputs: `ViolationListItem` also re-renders when `dependencies` or `capabilities` change, and
/// this does not depend on either. All three are value types, so the child compares equal and
/// SwiftUI skips it.
private struct ViolationRuleHeader: View {
    let ruleID: String
    let severity: Severity
    let isSuppressed: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ruleID)
                .font(.headline)
                .lineLimit(1)
            SeverityBadge(severity: severity)
            if isSuppressed {
                Label("Suppressed", systemImage: "eye.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The `file • Line n` caption.
private struct ViolationFileLocation: View {
    let filePath: String
    let line: Int

    var body: some View {
        HStack(spacing: 8) {
            Label(filePath, systemImage: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\u{2022}")
                .foregroundStyle(.secondary)
            Label("Line \(line)", systemImage: "number")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ViolationListItem: View {
    let violation: Violation
    var onOpenInXcode: (() -> Void)?

    @Environment(\.dependencies) var dependencies: DependencyContainer
    @Environment(\.appCapabilities) private var capabilities: Set<AppCapability>

    var body: some View {
        HStack(spacing: 12) {
            // Decorative — severity is also shown by the SeverityBadge text.
            Circle()
                .fill(severityColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                ViolationRuleHeader(
                    ruleID: violation.ruleID,
                    severity: violation.severity,
                    isSuppressed: violation.suppressed
                )
                Text(violation.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                ViolationFileLocation(filePath: violation.filePath, line: violation.line)
            }

            Spacer()

            openInXcodeButton
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu { contextMenuItems }
    }

    @ViewBuilder
    private var openInXcodeButton: some View {
        if capabilities.contains(.openInXcode), let onOpenInXcode = onOpenInXcode {
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
        if capabilities.contains(.openInXcode),
           let workspace = dependencies.workspaceManager.currentWorkspace {
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
