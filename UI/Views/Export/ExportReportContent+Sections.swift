//
//  ExportReportContent+Sections.swift
//  SwiftLintRuleStudio
//
//  Section views for the Export Report screen
//

import LintStudioUI
import SwiftLintRuleStudioCore
import SwiftUI

// MARK: - Format Selection

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

extension ExportReportContent {
    var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Format")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(ExportFormat.allCases) { format in
                    ExportFormatCard(
                        format: format,
                        isSelected: model.selectedFormat == format
                    ) { model.selectedFormat = format }
                }
            }
        }
    }
}

extension ExportReportContent {
    var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Include in Report")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Issue summary with counts by severity", isOn: $model.includeSummary)
                Toggle("Detailed issue list grouped by file", isOn: $model.includeDetailedList)
                Toggle("Code snippets for each violation", isOn: $model.includeCodeSnippets)
                    .disabled(model.selectedFormat != .html)
                Toggle("Rule configuration details", isOn: $model.includeRuleConfig)
                Toggle(isOn: $model.includeHistoricalTrends) {
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

extension ExportReportContent {
    var outputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Output")
                .font(.headline)

            HStack(spacing: 8) {
                Text("Save to")
                    .foregroundStyle(.secondary)

                TextField("Output path...", text: $model.outputPath)
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
        panel.allowedContentTypes = contentTypesForFormat(model.selectedFormat)
        panel.nameFieldStringValue = defaultFileName()
        panel.canCreateDirectories = true

        if let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            panel.directoryURL = desktopURL
        }

        panel.begin { response in
            if response == .OK, let url = panel.url {
                model.outputPath = url.path
            }
        }
    }

    func defaultFileName() -> String {
        let workspaceName = dependencies.workspaceManager.currentWorkspace?.name ?? "workspace"
        let timestamp = ExportFilename.timestamp()
        return "\(workspaceName)-lint-report-\(timestamp).\(model.selectedFormat.fileExtension)"
    }

    private func contentTypesForFormat(_ format: ExportFormat) -> [UTType] {
        switch format {
        case .html: [.html]
        case .json: [.json]
        case .csv: [.commaSeparatedText]
        }
    }
}

extension ExportReportContent {
    var actionSection: some View {
        HStack {
            if model.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading violations...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(model.violations.count) violations available for export")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.exportComplete {
                Label("Exported!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            Button("Export") {
                performExport()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.outputPath.isEmpty || model.violations.isEmpty || model.isExporting)
            .accessibilityIdentifier("ExportReportButton")
        }
    }

    func loadViolations() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else { return }

        // Set default output path
        if model.outputPath.isEmpty {
            if let desktop = FileManager.default.urls(
                for: .desktopDirectory, in: .userDomainMask
            ).first {
                model.outputPath = desktop
                    .appendingPathComponent(defaultFileName())
                    .path
            }
        }

        model.isLoading = true
        Task {
            let loaded = try? await dependencies.violationStorage.fetchViolations(
                filter: ViolationFilter(),
                workspaceId: workspace.id
            )
            model.violations = loaded ?? []
            model.isLoading = false
        }
    }

    func performExport() {
        guard !model.outputPath.isEmpty, !model.violations.isEmpty else { return }

        model.isExporting = true
        model.exportComplete = false

        let url = URL(fileURLWithPath: model.outputPath)
        let workspaceName = dependencies.workspaceManager.currentWorkspace?.name ?? "Unknown"

        Task {
            do {
                try writeReport(to: url, workspaceName: workspaceName)

                model.isExporting = false
                model.exportComplete = true

                // Reset after a delay
                try? await Task.sleep(for: .seconds(3))
                model.exportComplete = false
            } catch {
                model.isExporting = false
                model.errorMessage = error.localizedDescription
                model.showError = true
            }
        }
    }

    /// Writes the violations to `url` in the selected format.
    private func writeReport(to url: URL, workspaceName: String) throws {
        switch model.selectedFormat {
        case .html:
            let html = HTMLReportGenerator.generate(
                options: HTMLReportOptions(
                    violations: model.violations,
                    workspaceName: workspaceName,
                    // The composition root is where the clock belongs: everything below
                    // this line is a function of what it is handed. Spelled `Date.now`
                    // rather than `.now` on purpose: a leading-dot `.now` has no
                    // syntactic base type, so a linter cannot tell a wall clock from a
                    // monotonic one and deliberately classifies neither. Writing it that
                    // way would move this read somewhere no tool can see it, and a read
                    // reported where it belongs is better than one nothing can find.
                    generatedAt: Date.now,
                    includeSummary: model.includeSummary,
                    includeDetailedList: model.includeDetailedList,
                    includeCodeSnippets: model.includeCodeSnippets,
                    includeRuleConfig: model.includeRuleConfig,
                    ruleRegistry: dependencies.ruleRegistry
                )
            )
            try html.write(to: url, atomically: true, encoding: .utf8)

        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(model.violations)
            try data.write(to: url)

        case .csv:
            let csv = CSVReportGenerator.generate(violations: model.violations)
            try csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Import for UTType

import UniformTypeIdentifiers
