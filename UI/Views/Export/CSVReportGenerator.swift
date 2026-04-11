//
//  CSVReportGenerator.swift
//  SwiftLintRuleStudio
//
//  Generates a CSV export of violations
//

import Foundation
import SwiftLintRuleStudioCore

enum CSVReportGenerator {
    static func generate(violations: [Violation]) -> String {
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

        let isoFormatter = ISO8601DateFormatter()
        var csv = "\(header)\n"

        for violation in violations {
            let row = [
                escapeCSV(violation.ruleID),
                escapeCSV(violation.filePath),
                "\(violation.line)",
                violation.column.map { "\($0)" } ?? "",
                violation.severity.rawValue,
                escapeCSV(violation.message),
                isoFormatter.string(from: violation.detectedAt),
                violation.resolvedAt.map { isoFormatter.string(from: $0) } ?? "",
                violation.suppressed ? "true" : "false",
                violation.suppressionReason.map { escapeCSV($0) } ?? ""
            ].joined(separator: ",")
            csv += row + "\n"
        }

        return csv
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
