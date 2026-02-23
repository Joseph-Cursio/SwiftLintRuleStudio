//
//  VersionCompatibilityView.swift
//  SwiftLintRuleStudio
//
//  View for checking SwiftLint version compatibility
//

import SwiftUI

struct VersionCompatibilityView: View {
    @StateObject var viewModel: VersionCompatibilityViewModel

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
                .accessibilityHidden(true)
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
                        .accessibilityHidden(true)
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
                        .accessibilityHidden(true)
                    Text("No compatibility issues found")
                        .fontWeight(.semibold)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
            }

            if !report.removedRules.isEmpty {
                removedRulesSection(report.removedRules)
            }

            if !report.deprecatedRules.isEmpty {
                deprecatedRulesSection(report.deprecatedRules)
            }

            if !report.renamedRules.isEmpty {
                renamedRulesSection(report.renamedRules)
            }

            if !report.availableNewRules.isEmpty {
                newRulesAvailableSection(report.availableNewRules)
            }
        }
    }

}
