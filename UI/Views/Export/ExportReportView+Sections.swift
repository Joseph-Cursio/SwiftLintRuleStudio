//
//  ExportReportView+Sections.swift
//  SwiftLintRuleStudio
//
//  Section views for the Export Report screen
//

import SwiftUI
import SwiftLintRuleStudioCore

// MARK: - Format Selection

extension ExportReportView {
    var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Format")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(ExportFormat.allCases) { format in
                    ExportFormatCard(
                        format: format,
                        isSelected: selectedFormat == format,
                        onSelect: { selectedFormat = format }
                    )
                }
            }
        }
    }
}

private struct ExportFormatCard: View {
    let format: ExportFormat
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Image(systemName: format.iconName)
                    .font(.title2)
                    .accessibilityHidden(true)
                Text(format.rawValue)
                    .font(.headline)
                Text(format.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color(NSColor.separatorColor),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(format.rawValue) format")
    }
}

// MARK: - Content Options

extension ExportReportView {
    var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Include in Report")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Issue summary with counts by severity", isOn: $includeSummary)
                Toggle("Detailed issue list grouped by file", isOn: $includeDetailedList)
                Toggle("Code snippets for each violation", isOn: $includeCodeSnippets)
                    .disabled(selectedFormat != .html)
                Toggle("Rule configuration details", isOn: $includeRuleConfig)
                Toggle(isOn: $includeHistoricalTrends) {
                    HStack(spacing: 4) {
                        Text("Historical trend comparison")
                        Text("(future feature)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(true)
            }
            .toggleStyle(.checkbox)
        }
    }
}

// MARK: - Output Options

extension ExportReportView {
    var outputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Output")
                .font(.headline)

            HStack(spacing: 8) {
                Text("Save to")
                    .foregroundStyle(.secondary)

                TextField("Output path...", text: $outputPath)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("ExportReportOutputPath")

                Button("Browse...") {
                    browseForOutputPath()
                }
            }
        }
    }

    func browseForOutputPath() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = contentTypesForFormat(selectedFormat)
        panel.nameFieldStringValue = defaultFileName()
        panel.canCreateDirectories = true

        if let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            panel.directoryURL = desktopURL
        }

        panel.begin { response in
            if response == .OK, let url = panel.url {
                outputPath = url.path
            }
        }
    }

    func defaultFileName() -> String {
        let workspaceName = dependencies.workspaceManager.currentWorkspace?.name ?? "workspace"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date.now)
        return "\(workspaceName)-lint-report-\(timestamp).\(selectedFormat.fileExtension)"
    }

    private func contentTypesForFormat(_ format: ExportFormat) -> [UTType] {
        switch format {
        case .html: [.html]
        case .json: [.json]
        case .csv: [.commaSeparatedText]
        }
    }
}

// MARK: - Actions

extension ExportReportView {
    var actionSection: some View {
        HStack {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading violations...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(violations.count) violations available for export")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if exportComplete {
                Label("Exported!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            Button("Export") {
                performExport()
            }
            .buttonStyle(.borderedProminent)
            .disabled(outputPath.isEmpty || violations.isEmpty || isExporting)
            .accessibilityIdentifier("ExportReportButton")
        }
    }

    func loadViolations() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else { return }

        // Set default output path
        if outputPath.isEmpty {
            if let desktop = FileManager.default.urls(
                for: .desktopDirectory, in: .userDomainMask
            ).first {
                outputPath = desktop
                    .appendingPathComponent(defaultFileName())
                    .path
            }
        }

        isLoading = true
        Task {
            let loaded = try? await dependencies.violationStorage.fetchViolations(
                filter: ViolationFilter(),
                workspaceId: workspace.id
            )
            violations = loaded ?? []
            isLoading = false
        }
    }

    func performExport() {
        guard !outputPath.isEmpty, !violations.isEmpty else { return }

        isExporting = true
        exportComplete = false

        let url = URL(fileURLWithPath: outputPath)
        let workspaceName = dependencies.workspaceManager.currentWorkspace?.name ?? "Unknown"

        Task {
            do {
                switch selectedFormat {
                case .html:
                    let html = HTMLReportGenerator.generate(
                        options: HTMLReportOptions(
                            violations: violations,
                            workspaceName: workspaceName,
                            includeSummary: includeSummary,
                            includeDetailedList: includeDetailedList,
                            includeCodeSnippets: includeCodeSnippets,
                            includeRuleConfig: includeRuleConfig,
                            ruleRegistry: dependencies.ruleRegistry
                        )
                    )
                    try html.write(to: url, atomically: true, encoding: .utf8)

                case .json:
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(violations)
                    try data.write(to: url)

                case .csv:
                    let csv = CSVReportGenerator.generate(violations: violations)
                    try csv.write(to: url, atomically: true, encoding: .utf8)
                }

                isExporting = false
                exportComplete = true

                // Reset after a delay
                try? await Task.sleep(for: .seconds(3))
                exportComplete = false
            } catch {
                isExporting = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Import for UTType

import UniformTypeIdentifiers
