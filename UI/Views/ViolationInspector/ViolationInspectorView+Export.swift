import SwiftUI
import UniformTypeIdentifiers

extension ViolationInspectorView {
    func exportViolations(scope: ViolationExportScope, format: ViolationExportFormat) {
        let violationsToExport = violationsForExport(scope: scope)
        guard !violationsToExport.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .json ? [.json] : [.commaSeparatedText]
        panel.nameFieldStringValue = exportFileName(scope: scope, format: format)
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task {
                do {
                    switch format {
                    case .json:
                        try exportToJSON(violations: violationsToExport, url: url)
                    case .csv:
                        try exportToCSV(violations: violationsToExport, url: url)
                    }
                } catch {
                    print("Export failed: \(error)")
                }
            }
        }
    }

    func violationsForExport(scope: ViolationExportScope) -> [Violation] {
        switch scope {
        case .filtered:
            return viewModel.filteredViolations
        case .selected:
            let selected = viewModel.selectedViolationIds
            return viewModel.filteredViolations.filter { selected.contains($0.id) }
        }
    }

    func exportFileName(scope: ViolationExportScope, format: ViolationExportFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let scopeLabel = scope.rawValue.lowercased()
        let extensionLabel = format == .json ? "json" : "csv"
        return "violations_\(scopeLabel)_\(timestamp).\(extensionLabel)"
    }

    func exportToJSON(violations: [Violation], url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(violations)
        try data.write(to: url)
    }

    func exportToCSV(violations: [Violation], url: URL) throws {
        let header = [
            "Rule ID",
            "File Path",
            "Line",
            "Column",
            "Severity",
            "Message",
            "Detected At",
            "Resolved At",
            "Suppressed",
            "Suppression Reason"
        ].joined(separator: ",")
        var csv = "\(header)\n"

        for violation in violations {
            let line = [
                violation.ruleID,
                violation.filePath,
                "\(violation.line)",
                violation.column.map { "\($0)" } ?? "",
                violation.severity.rawValue,
                "\"\(violation.message.replacingOccurrences(of: "\"", with: "\"\""))\"",
                ISO8601DateFormatter().string(from: violation.detectedAt),
                violation.resolvedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                violation.suppressed ? "true" : "false",
                violation.suppressionReason.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" } ?? ""
            ].joined(separator: ",")
            csv += line + "\n"
        }

        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
