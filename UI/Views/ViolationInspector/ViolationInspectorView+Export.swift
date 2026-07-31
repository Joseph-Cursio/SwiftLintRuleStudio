import SwiftLintRuleStudioCore
import SwiftUI
import UniformTypeIdentifiers

extension ViolationInspectorView {
    func exportViolations(scope: ViolationExportScope, format: ViolationExportFormat) {
        let violationsToExport = Self.violationsForExport(
            scope: scope,
            filtered: viewModel.filteredViolations,
            selectedIds: viewModel.selectedViolationIds
        )
        guard !violationsToExport.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .json ? [.json] : [.commaSeparatedText]
        panel.nameFieldStringValue = Self.exportFileName(scope: scope, format: format)
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task {
                try? Self.export(violations: violationsToExport, to: url, as: format)
            }
        }
    }

    /// The violations an export covers: everything currently filtered, or just
    /// the subset the user has selected. Selection is intersected with the
    /// filtered list, so a violation selected and then filtered away is not
    /// silently exported.
    static func violationsForExport(
        scope: ViolationExportScope,
        filtered: [Violation],
        selectedIds: Set<UUID>
    ) -> [Violation] {
        switch scope {
        case .filtered:
            return filtered
        case .selected:
            return filtered.filter { selectedIds.contains($0.id) }
        }
    }

    static func exportFileName(
        scope: ViolationExportScope,
        format: ViolationExportFormat
    ) -> String {
        let timestamp = ExportFilename.timestamp()
        let scopeLabel = scope.rawValue.lowercased()
        let extensionLabel = format == .json ? "json" : "csv"
        return "violations_\(scopeLabel)_\(timestamp).\(extensionLabel)"
    }

    static func export(
        violations: [Violation],
        to url: URL,
        as format: ViolationExportFormat
    ) throws {
        switch format {
        case .json:
            try exportToJSON(violations: violations, url: url)
        case .csv:
            try exportToCSV(violations: violations, url: url)
        }
    }

    static func exportToJSON(violations: [Violation], url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(violations)
        try data.write(to: url)
    }

    static func exportToCSV(violations: [Violation], url: URL) throws {
        let csv = CSVReportGenerator.generate(violations: violations)
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
