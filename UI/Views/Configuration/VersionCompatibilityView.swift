//
//  VersionCompatibilityView.swift
//  SwiftLintRuleStudio
//
//  View for checking SwiftLint version compatibility
//

import SwiftUI

struct VersionCompatibilityView: View {
    @StateObject private var viewModel: VersionCompatibilityViewModel

    init(
        checker: VersionCompatibilityCheckerProtocol,
        swiftLintCLI: SwiftLintCLIProtocol,
        configPath: URL?
    ) {
        _viewModel = StateObject(wrappedValue: VersionCompatibilityViewModel(
            checker: checker,
            swiftLintCLI: swiftLintCLI,
            configPath: configPath
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                if viewModel.isChecking {
                    ProgressView("Checking compatibility...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if let error = viewModel.error {
                    errorSection(error)
                } else if let report = viewModel.report {
                    reportSection(report)
                } else {
                    emptyState
                }
            }
            .padding()
        }
        .navigationTitle("Version Compatibility")
        .onAppear {
            viewModel.checkCompatibility()
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("SwiftLint Version")
                    .font(.headline)
                if let version = viewModel.currentVersion {
                    Text(version)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                } else {
                    Text("Not detected")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Check") {
                viewModel.checkCompatibility()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isChecking)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }

    private func errorSection(_ error: Error) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(error.localizedDescription)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Click \"Check\" to analyze your configuration compatibility")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func reportSection(_ report: CompatibilityReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary badge
            if report.hasIssues {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("\(report.totalIssueCount) issue\(report.totalIssueCount == 1 ? "" : "s") found")
                        .fontWeight(.semibold)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("No compatibility issues found")
                        .fontWeight(.semibold)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
            }

            // Removed rules (red)
            if !report.removedRules.isEmpty {
                issueSection(
                    title: "Removed Rules",
                    subtitle: "These rules no longer exist and must be removed",
                    color: .red,
                    icon: "xmark.circle.fill"
                ) {
                    ForEach(report.removedRules) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.ruleId)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.semibold)
                                Text(rule.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Removed in \(rule.removedInVersion)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            // Deprecated rules (orange)
            if !report.deprecatedRules.isEmpty {
                issueSection(
                    title: "Deprecated Rules",
                    subtitle: "These rules still work but should be migrated",
                    color: .orange,
                    icon: "exclamationmark.triangle.fill"
                ) {
                    ForEach(report.deprecatedRules) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.ruleId)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.semibold)
                                Text(rule.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let replacement = rule.replacement {
                                Text("Use: \(replacement)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }

            // Renamed rules (yellow)
            if !report.renamedRules.isEmpty {
                issueSection(
                    title: "Renamed Rules",
                    subtitle: "These rules have been renamed",
                    color: .yellow,
                    icon: "arrow.right.circle.fill"
                ) {
                    ForEach(report.renamedRules) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(rule.oldRuleId)
                                        .font(.system(.body, design: .monospaced))
                                        .strikethrough()
                                    Image(systemName: "arrow.right")
                                        .font(.caption)
                                    Text(rule.newRuleId)
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.semibold)
                                }
                            }
                            Spacer()
                            Button("Fix") {
                                viewModel.applyRenaming(rule)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Button("Fix All Renames") {
                        viewModel.applyAllFixes()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
            }

            // New rules available (green/informational)
            if !report.availableNewRules.isEmpty {
                issueSection(
                    title: "New Rules Available",
                    subtitle: "Rules added in recent SwiftLint versions that you could enable",
                    color: .green,
                    icon: "plus.circle.fill"
                ) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(report.availableNewRules, id: \.self) { ruleId in
                            Text(ruleId)
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .clipShape(.rect(cornerRadius: 4))
                        }
                    }
                }
            }
        }
    }

    private func issueSection<Content: View>(
        title: String,
        subtitle: String,
        color: Color,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 8))
        }
    }
}
