//
//  GitBranchDiffView.swift
//  SwiftLintRuleStudio
//
//  View for comparing .swiftlint.yml across git branches
//

import SwiftUI

struct GitBranchDiffView: View {
    @StateObject private var viewModel: GitBranchDiffViewModel

    init(service: GitBranchDiffServiceProtocol, workspacePath: URL?) {
        _viewModel = StateObject(wrappedValue: GitBranchDiffViewModel(
            service: service,
            workspacePath: workspacePath
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isNotGitRepo {
                    notGitRepoSection
                } else if viewModel.isLoading && viewModel.availableRefs == nil {
                    ProgressView("Loading git refs...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    branchPickerSection

                    if viewModel.isLoading && viewModel.availableRefs != nil {
                        ProgressView("Comparing configurations...")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }

                    if let error = viewModel.error {
                        errorSection(error)
                    }

                    if let result = viewModel.comparisonResult {
                        comparisonResultSection(result)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Branch Config Diff")
        .onAppear {
            viewModel.loadRefs()
        }
    }

    // MARK: - Sections

    private var notGitRepoSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Not a Git Repository")
                .font(.headline)
            Text("This workspace is not inside a git repository. Branch diff requires git.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var branchPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let refs = viewModel.availableRefs {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    Text("Current branch: ")
                        .font(.headline)
                    Text(refs.currentBranch)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Compare with:")
                            .font(.subheadline)

                        Picker("Branch", selection: Binding(
                            get: { viewModel.selectedRef ?? "" },
                            set: { viewModel.selectedRef = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("Select a branch...").tag("")

                            if refs.branches.count > 1 {
                                Section("Branches") {
                                    ForEach(refs.branches.filter { $0 != refs.currentBranch }, id: \.self) { branch in
                                        Text(branch).tag(branch)
                                    }
                                }
                            }

                            if !refs.tags.isEmpty {
                                Section("Tags") {
                                    ForEach(refs.tags, id: \.self) { tag in
                                        Text(tag).tag(tag)
                                    }
                                }
                            }
                        }
                        .frame(minWidth: 200)
                    }

                    Button("Compare") {
                        viewModel.compareWithSelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedRef == nil || viewModel.isLoading)
                }
            }
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

    private func comparisonResultSection(_ result: ConfigComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary
            HStack {
                Text("Comparison Results")
                    .font(.headline)
                Spacer()
                Text("\(result.totalDifferences) difference\(result.totalDifferences == 1 ? "" : "s")")
                    .foregroundStyle(result.totalDifferences > 0 ? .orange : .green)
                    .fontWeight(.semibold)
            }

            if result.totalDifferences == 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Configurations are identical")
                        .fontWeight(.semibold)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
            } else {
                // Rules only in current
                if !result.onlyInFirst.isEmpty {
                    diffSection(
                        title: "Only in Current Branch",
                        rules: result.onlyInFirst,
                        color: .blue,
                        icon: "minus.circle.fill"
                    )
                }

                // Rules only in selected branch
                if !result.onlyInSecond.isEmpty {
                    diffSection(
                        title: "Only in \(viewModel.selectedRef ?? "other branch")",
                        rules: result.onlyInSecond,
                        color: .purple,
                        icon: "plus.circle.fill"
                    )
                }

                // Rules with different settings
                if !result.inBothDifferent.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            Text("Different Settings")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }

                        ForEach(result.inBothDifferent) { diff in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(diff.ruleId)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.semibold)
                                ForEach(diff.differences, id: \.self) { detail in
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.leading, 24)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(.rect(cornerRadius: 8))
                }

                // Full YAML diff
                DisclosureGroup("Full YAML Diff") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                        Text(result.diff.before.isEmpty ? "(no config)" : result.diff.before)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(.rect(cornerRadius: 4))

                        Text(viewModel.selectedRef ?? "Other")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.purple)
                        Text(result.diff.after.isEmpty ? "(no config)" : result.diff.after)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(.rect(cornerRadius: 4))
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(.rect(cornerRadius: 8))
            }
        }
    }

    private func diffSection(title: String, rules: [String], color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            ForEach(rules, id: \.self) { ruleId in
                Text(ruleId)
                    .font(.system(.body, design: .monospaced))
                    .padding(.leading, 24)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }
}
