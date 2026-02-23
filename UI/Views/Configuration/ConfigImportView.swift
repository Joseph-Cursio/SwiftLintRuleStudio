//
//  ConfigImportView.swift
//  SwiftLintRuleStudio
//
//  View for importing SwiftLint configs from URLs
//

import SwiftUI

struct ConfigImportView: View {
    @StateObject private var viewModel: ConfigImportViewModel

    init(importService: ConfigImportServiceProtocol, configPath: URL?) {
        _viewModel = StateObject(wrappedValue: ConfigImportViewModel(
            importService: importService,
            configPath: configPath
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                urlInputSection
                importModeSection

                if viewModel.isFetching {
                    ProgressView("Fetching configuration...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if let error = viewModel.error {
                    errorSection(error)
                }

                if viewModel.importComplete {
                    successSection
                }

                if let preview = viewModel.preview {
                    previewSection(preview)
                }
            }
            .padding()
        }
        .navigationTitle("Import Configuration")
    }

    // MARK: - Sections

    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import from URL")
                .font(.headline)

            HStack {
                TextField("https://...", text: $viewModel.urlString)
                    .textFieldStyle(.roundedBorder)

                Button("Fetch") {
                    viewModel.fetchPreview()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.urlString.isEmpty || viewModel.isFetching)
            }

            Text("Supports GitHub raw URLs, Gist URLs, or any HTTPS URL to a .swiftlint.yml")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }

    private var importModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import Mode")
                .font(.headline)

            Picker("Mode", selection: $viewModel.importMode) {
                Text("Merge (imported rules override conflicts)").tag(ImportMode.merge)
                Text("Replace (replace entire config)").tag(ImportMode.replace)
            }
            .pickerStyle(.radioGroup)
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

    private var successSection: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Configuration imported successfully!")
                .fontWeight(.semibold)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
    }

    private func previewSection(_ preview: ConfigImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                if preview.validationErrors.isEmpty {
                    Label("Valid", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("\(preview.validationErrors.count) warning(s)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            if !preview.validationErrors.isEmpty {
                ForEach(preview.validationErrors, id: \.self) { warning in
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(warning)
                            .font(.caption)
                    }
                }
            }

            // Show fetched YAML
            VStack(alignment: .leading, spacing: 4) {
                Text("Fetched Configuration")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                ScrollView(.horizontal) {
                    Text(preview.fetchedYAML)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                }
                .frame(maxHeight: 200)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(.rect(cornerRadius: 8))
            }

            // Show diff if available
            if let diff = preview.diff, diff.hasChanges {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Changes from Current Config")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    diffSummary(diff)
                }
            }

            // Apply button
            Button("Apply Import") {
                viewModel.applyImport()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isImporting || viewModel.importComplete)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }

    private func diffSummary(_ diff: YAMLConfigurationEngine.ConfigDiff) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !diff.addedRules.isEmpty {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("\(diff.addedRules.count) rule(s) to add")
                }
            }
            if !diff.removedRules.isEmpty {
                HStack {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text("\(diff.removedRules.count) rule(s) to remove")
                }
            }
            if !diff.modifiedRules.isEmpty {
                HStack {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("\(diff.modifiedRules.count) rule(s) to modify")
                }
            }
        }
    }
}
