//
//  ViolationListItem.swift
//  SwiftLintRuleStudio
//
//  Component for displaying a violation in a list
//

import SwiftUI

struct ViolationListItem: View {
    let violation: Violation
    var onOpenInXcode: (() -> Void)? = nil
    
    @EnvironmentObject var dependencies: DependencyContainer
    
    var body: some View {
        HStack(spacing: 12) {
            // Severity indicator
            Circle()
                .fill(severityColor)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                // Rule ID and severity
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(violation.ruleID)
                        .font(.headline)
                        .lineLimit(1)
                    
                    SeverityBadge(severity: violation.severity)
                    
                    if violation.suppressed {
                        Label("Suppressed", systemImage: "eye.slash")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Message
                Text(violation.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                // File and line
                HStack(spacing: 8) {
                    Label(violation.filePath, systemImage: "doc.text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Label("Line \(violation.line)", systemImage: "number")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Open in Xcode button (compact)
            if let onOpenInXcode = onOpenInXcode {
                Button {
                    onOpenInXcode()
                } label: {
                    Image(systemName: "arrow.right.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open in Xcode (⌘O)")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
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
    }
    
    private func openInXcode(workspace: Workspace) async {
        do {
            _ = try await dependencies.xcodeIntegrationService.openFile(
                at: violation.filePath,
                line: violation.line,
                column: violation.column,
                in: workspace
            )
        } catch {
            // Error handling is done at the service level or can be shown via alert
            print("Failed to open file in Xcode: \(error)")
        }
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

struct SeverityBadge: View {
    let severity: Severity
    
    var body: some View {
        Text(severity.rawValue.uppercased())
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(severityColor.opacity(0.2))
            .foregroundColor(severityColor)
            .cornerRadius(4)
    }
    
    private var severityColor: Color {
        switch severity {
        case .error:
            return .red
        case .warning:
            return .orange
        }
    }
}



