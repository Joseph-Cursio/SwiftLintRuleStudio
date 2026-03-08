//
//  ViolationDetailView+Sections.swift
//  SwiftLintRuleStudio
//
//  Section views for the violation detail screen
//

import SwiftUI

struct ViolationDetailHeaderView: View {
    let violation: Violation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SeverityBadge(severity: violation.severity)

                if violation.suppressed {
                    Label("Suppressed", systemImage: "eye.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if violation.resolvedAt != nil {
                    Label("Resolved", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }

            Text("Rule: \(violation.ruleID)")
                .font(.title2)
                .fontWeight(.bold)
        }
    }
}

struct ViolationDetailLocationView: View {
    let violation: Violation
    @Binding var isOpeningInXcode: Bool
    let openInXcode: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.headline)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("File")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(violation.filePath)
                        .font(.body)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Line")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(violation.line)")
                        .font(.body)
                }

                if let column = violation.column {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Column")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(column)")
                            .font(.body)
                    }
                }
            }

            Button(action: openInXcode) {
                if isOpeningInXcode {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Label("Open in Xcode", systemImage: "arrow.right.circle")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isOpeningInXcode)
            .accessibilityIdentifier("ViolationDetailOpenInXcodeButton")
        }
    }
}

struct ViolationDetailMessageView: View {
    let violation: Violation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message")
                .font(.headline)

            Text(violation.message)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}

struct ViolationDetailCodeSnippetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Code Context")
                .font(.headline)

            // TODO: Load and display code snippet from file
            Text("Code snippet loading not yet implemented")
                .font(.body)
                .foregroundStyle(.secondary)
                .italic()
        }
    }
}

struct ViolationDetailActionsView: View {
    let violation: Violation
    @Binding var showSuppressDialog: Bool
    let onResolve: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 12) {
                if !violation.suppressed {
                    Button {
                        showSuppressDialog = true
                    } label: {
                        Label("Suppress", systemImage: "eye.slash")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("ViolationDetailSuppressButton")
                }

                if violation.resolvedAt == nil {
                    Button(action: onResolve) {
                        Label("Mark as Resolved", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
