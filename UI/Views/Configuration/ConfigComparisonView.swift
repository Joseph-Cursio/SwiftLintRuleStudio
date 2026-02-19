//
//  ConfigComparisonView.swift
//  SwiftLintRuleStudio
//
//  Side-by-side comparison of SwiftLint configurations from two workspaces
//

import SwiftUI

struct ConfigComparisonView: View {
    @StateObject private var viewModel: ConfigComparisonViewModel

    init(service: ConfigComparisonServiceProtocol, currentWorkspace: Workspace?) {
        _viewModel = StateObject(wrappedValue: ConfigComparisonViewModel(
            service: service,
            currentWorkspace: currentWorkspace
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Workspace selectors
            workspaceSelectorsView
                .padding()

            Divider()

            // Results
            if viewModel.isComparing {
                ProgressView("Comparing configurations...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = viewModel.comparisonResult {
                comparisonResultView(result)
            } else {
                emptyStateView
            }
        }
        .navigationTitle("Compare Configs")
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error?.localizedDescription ?? "An unknown error occurred.")
        }
    }

    private var workspaceSelectorsView: some View {
        HStack(spacing: 16) {
            // Left workspace
            VStack(alignment: .leading, spacing: 4) {
                Text("Left Config")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    if let path = viewModel.leftWorkspacePath {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.blue)
                            .accessibilityHidden(true)
                        Text(path.deletingLastPathComponent().lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("No config selected")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Browse...") {
                        viewModel.selectLeftWorkspace()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)

            Image(systemName: "arrow.left.arrow.right")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            // Right workspace
            VStack(alignment: .leading, spacing: 4) {
                Text("Right Config")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    if let path = viewModel.rightWorkspacePath {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text(path.deletingLastPathComponent().lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("No config selected")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Browse...") {
                        viewModel.selectRightWorkspace()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)

            Button("Compare") {
                viewModel.compare()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.leftWorkspacePath == nil || viewModel.rightWorkspacePath == nil)
        }
    }

    private func comparisonResultView(_ result: ConfigComparisonResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Summary
                summaryView(result)

                Divider()

                // Only in Left
                if !result.onlyInFirst.isEmpty {
                    ruleListSection(
                        title: "Only in Left",
                        icon: "minus.circle.fill",
                        color: .red,
                        rules: result.onlyInFirst
                    )
                }

                // Only in Right
                if !result.onlyInSecond.isEmpty {
                    ruleListSection(
                        title: "Only in Right",
                        icon: "plus.circle.fill",
                        color: .green,
                        rules: result.onlyInSecond
                    )
                }

                // Different settings
                if !result.inBothDifferent.isEmpty {
                    differenceSection(result.inBothDifferent)
                }

                Divider()

                // Full diff
                FullYAMLDiffView(diff: result.diff)
            }
            .padding()
        }
    }

    private func summaryView(_ result: ConfigComparisonResult) -> some View {
        HStack(spacing: 24) {
            summaryItem(
                count: result.onlyInFirst.count,
                label: "Only in Left",
                color: .red
            )
            summaryItem(
                count: result.onlyInSecond.count,
                label: "Only in Right",
                color: .green
            )
            summaryItem(
                count: result.inBothDifferent.count,
                label: "Different",
                color: .orange
            )
            summaryItem(
                count: result.inBothSame.count,
                label: "Same",
                color: .secondary
            )
        }
    }

    private func summaryItem(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func ruleListSection(
        title: String,
        icon: String,
        color: Color,
        rules: [String]
    ) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rules, id: \.self) { ruleId in
                    Text(ruleId)
                        .font(.system(.body, design: .monospaced))
                        .padding(.vertical, 2)
                }
            }
        } label: {
            Label("\(title) (\(rules.count))", systemImage: icon)
                .foregroundStyle(color)
        }
    }

    private func differenceSection(_ diffs: [RuleComparisonDiff]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(diffs) { diff in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diff.ruleId)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)

                        ForEach(diff.differences, id: \.self) { difference in
                            Text(difference)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 16)
                        }
                    }
                    .padding(.vertical, 4)

                    if diff.id != diffs.last?.id {
                        Divider()
                    }
                }
            }
        } label: {
            Label("Differences (\(diffs.count))", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Compare Configurations")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Select two SwiftLint configuration files to compare their rules and settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Full YAML Diff View

struct FullYAMLDiffView: View {
    let diff: YAMLConfigurationEngine.ConfigDiff

    var body: some View {
        DisclosureGroup("Full YAML Diff") {
            HStack(alignment: .top, spacing: 16) {
                yamlPane(title: "Left", content: diff.before)
                yamlPane(title: "Right", content: diff.after)
            }
        }
    }

    private func yamlPane(
        title: String,
        content: String
    ) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 400)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 4))
        }
    }
}
