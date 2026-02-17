//
//  MigrationAssistantView.swift
//  SwiftLintRuleStudio
//
//  View for migrating SwiftLint configs between versions
//

import SwiftUI

struct MigrationAssistantView: View {
    @StateObject private var viewModel: MigrationAssistantViewModel

    init(
        assistant: MigrationAssistantProtocol,
        swiftLintCLI: SwiftLintCLIProtocol,
        configPath: URL?
    ) {
        _viewModel = StateObject(wrappedValue: MigrationAssistantViewModel(
            assistant: assistant,
            swiftLintCLI: swiftLintCLI,
            configPath: configPath
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                versionSection
                migrationPlanSection
                diffPreviewSection
            }
            .padding()
        }
        .navigationTitle("Migration Assistant")
    }

    // MARK: - Sections

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Version Migration")
                .font(.headline)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Previous Version")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g. 0.45.0", text: $viewModel.previousVersion)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }

                Image(systemName: "arrow.right")
                    .font(.title2)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Version")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let version = viewModel.currentVersion {
                        Text(version)
                            .font(.body)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    } else {
                        Text("Auto-detected")
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button("Detect Migrations") {
                    viewModel.detectMigrations()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.previousVersion.isEmpty || viewModel.isDetecting)
            }

            if viewModel.isDetecting {
                ProgressView("Detecting migrations...")
            }

            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var migrationPlanSection: some View {
        if let plan = viewModel.migrationPlan {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Migration Plan")
                        .font(.headline)
                    Spacer()
                    Text("\(plan.totalSteps) step\(plan.totalSteps == 1 ? "" : "s")")
                        .foregroundColor(.secondary)
                }

                if plan.steps.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("No migrations needed!")
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    ForEach(plan.steps) { step in
                        stepRow(step)
                    }

                    HStack {
                        if !plan.autoApplyableSteps.isEmpty {
                            Button("Preview Changes") {
                                viewModel.previewChanges()
                            }
                            .buttonStyle(.bordered)
                        }

                        if !plan.manualSteps.isEmpty {
                            Text("\(plan.manualSteps.count) manual step(s) require your attention")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var diffPreviewSection: some View {
        if let diff = viewModel.previewDiff {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preview of Changes")
                    .font(.headline)

                if diff.hasChanges {
                    VStack(alignment: .leading, spacing: 8) {
                        if !diff.addedRules.isEmpty {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.green)
                                Text("\(diff.addedRules.count) rule(s) to add")
                            }
                        }
                        if !diff.removedRules.isEmpty {
                            HStack {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                                Text("\(diff.removedRules.count) rule(s) to remove")
                            }
                        }
                        if !diff.modifiedRules.isEmpty {
                            HStack {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundColor(.orange)
                                Text("\(diff.modifiedRules.count) rule(s) to modify")
                            }
                        }
                    }

                    DisclosureGroup("Full Diff") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Before")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                            Text(diff.before.isEmpty ? "(empty)" : diff.before)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(4)

                            Text("After")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            Text(diff.after.isEmpty ? "(empty)" : diff.after)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(4)
                        }
                    }

                    HStack {
                        Button("Apply All Auto-Fixes") {
                            viewModel.applyMigration()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isMigrating || viewModel.migrationComplete)

                        if viewModel.migrationComplete {
                            Label("Migration applied!", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("No changes needed")
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func stepRow(_ step: MigrationStep) -> some View {
        HStack {
            Image(systemName: step.iconName)
                .foregroundColor(step.canAutoApply ? .blue : .orange)
                .frame(width: 20)

            Text(step.description)
                .font(.system(.body, design: .monospaced))

            Spacer()

            if step.canAutoApply {
                Text("Auto")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            } else {
                Text("Manual")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
}
