//
//  HTMLReportGenerator.swift
//  SwiftLintRuleStudio
//
//  Generates an HTML lint report with embedded CSS
//

import Foundation
import SwiftLintRuleStudioCore
import LintStudioCore

struct HTMLReportOptions {
    let violations: [Violation]
    let workspaceName: String
    let includeSummary: Bool
    let includeDetailedList: Bool
    let includeCodeSnippets: Bool
    let includeRuleConfig: Bool
    let ruleRegistry: RuleRegistry
}

enum HTMLReportGenerator {
    static func generate(options: HTMLReportOptions) -> String {
        let violations = options.violations
        let errorCount = violations.filter { $0.severity == .error }.count
        let warningCount = violations.filter { $0.severity == .warning }.count
        let fileCount = Set(violations.map(\.filePath)).count
        let ruleCount = Set(violations.map(\.ruleID)).count
        let timestamp = DateFormatter.localizedString(
            from: Date.now,
            dateStyle: .long,
            timeStyle: .short
        )

        var body = ""

        if options.includeSummary {
            body += summarySection(
                total: violations.count,
                errors: errorCount,
                warnings: warningCount,
                files: fileCount,
                rules: ruleCount
            )
        }

        if options.includeDetailedList {
            body += detailedListSection(
                violations: violations,
                includeCodeSnippets: options.includeCodeSnippets
            )
        }

        if options.includeRuleConfig {
            body += ruleConfigSection(
                violations: violations,
                ruleRegistry: options.ruleRegistry
            )
        }

        return HTMLReportTemplate.wrapInHTML(
            title: "\(options.workspaceName) \u{2014} Lint Report",
            timestamp: timestamp,
            body: body
        )
    }

    // MARK: - Sections

    private static func summarySection(
        total: Int,
        errors: Int,
        warnings: Int,
        files: Int,
        rules: Int
    ) -> String {
        """
        <section class="summary">
          <h2>Summary</h2>
          <div class="cards">
            <div class="card">
              <div class="card-value">\(total)</div>
              <div class="card-label">Total Violations</div>
            </div>
            <div class="card card-error">
              <div class="card-value">\(errors)</div>
              <div class="card-label">Errors</div>
            </div>
            <div class="card card-warning">
              <div class="card-value">\(warnings)</div>
              <div class="card-label">Warnings</div>
            </div>
            <div class="card">
              <div class="card-value">\(files)</div>
              <div class="card-label">Files Affected</div>
            </div>
            <div class="card">
              <div class="card-value">\(rules)</div>
              <div class="card-label">Rules Triggered</div>
            </div>
          </div>
        </section>
        """
    }

    private static func detailedListSection(
        violations: [Violation],
        includeCodeSnippets: Bool
    ) -> String {
        let grouped = Dictionary(grouping: violations, by: \.filePath)
        let sortedFiles = grouped.keys.sorted()

        var html = "<section class=\"details\"><h2>Violations by File</h2>\n"

        for file in sortedFiles {
            let fileViolations = grouped[file] ?? []
            let fileName = URL(fileURLWithPath: file).lastPathComponent
            html += """
              <div class="file-group">
                <h3>\(HTMLEscaping.escape(fileName))
                  <span class="file-count">\(fileViolations.count) violations</span>
                </h3>
                <p class="file-path">\(HTMLEscaping.escape(file))</p>
                <table>
                  <thead>
                    <tr>
                      <th>Line</th><th>Severity</th><th>Rule</th><th>Message</th>
                    </tr>
                  </thead>
                  <tbody>
            """

            for violation in fileViolations.sorted(by: { $0.line < $1.line }) {
                let severityClass = violation.severity == .error ? "severity-error" : "severity-warning"
                let severityLabel = violation.severity.rawValue.capitalized
                html += """
                    <tr>
                      <td class="line-num">\(violation.line)</td>
                      <td class="\(severityClass)">\(severityLabel)</td>
                      <td class="rule-id">\(HTMLEscaping.escape(violation.ruleID))</td>
                      <td>\(HTMLEscaping.escape(violation.message))</td>
                    </tr>
                """

                if includeCodeSnippets {
                    if let snippet = loadCodeSnippet(
                        filePath: file,
                        line: violation.line
                    ) {
                        html += """
                            <tr class="snippet-row">
                              <td colspan="4"><pre class="snippet">\(HTMLEscaping.escape(snippet))</pre></td>
                            </tr>
                        """
                    }
                }
            }

            html += "  </tbody></table></div>\n"
        }

        html += "</section>\n"
        return html
    }

    private static func ruleConfigSection(
        violations: [Violation],
        ruleRegistry: RuleRegistry
    ) -> String {
        let ruleIds = Set(violations.map(\.ruleID)).sorted()

        var html = "<section class=\"rule-config\"><h2>Rule Details</h2>\n"

        for ruleId in ruleIds {
            let count = violations.filter { $0.ruleID == ruleId }.count
            let rule = ruleRegistry.rules.first { $0.id == ruleId }
            let description = rule?.description ?? "No description available"
            let autoFix = rule?.supportsAutocorrection == true ? "Yes" : "No"
            let category = rule?.category.displayName ?? "Unknown"

            html += """
              <div class="rule-detail">
                <h4>\(HTMLEscaping.escape(ruleId))
                  <span class="file-count">\(count) violations</span>
                </h4>
                <p>\(HTMLEscaping.escape(description))</p>
                <div class="rule-meta">
                  <span>Category: \(HTMLEscaping.escape(category))</span>
                  <span>Auto-fixable: \(autoFix)</span>
                </div>
              </div>
            """
        }

        html += "</section>\n"
        return html
    }

    // MARK: - Helpers

    private static func loadCodeSnippet(filePath: String, line: Int) -> String? {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return nil
        }
        let lines = content.components(separatedBy: .newlines)
        let start = max(0, line - 2)
        let end = min(lines.count - 1, line + 1)

        guard start <= end else { return nil }

        return (start...end).map { idx in
            let marker = idx == line - 1 ? ">" : " "
            let lineNum = String(format: "%4d", idx + 1)
            return "\(marker) \(lineNum) | \(lines[idx])"
        }.joined(separator: "\n")
    }
}
