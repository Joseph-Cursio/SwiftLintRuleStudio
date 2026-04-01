import SwiftUI
import SwiftLintRuleStudioCore

extension RuleDetailView {
    private func convertDocumentationToPlainText(markdown: String) -> String {
        // Strip HTML tags
        var stripped = markdown.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )

        // Remove inline styles
        stripped = stripped.replacingOccurrences(
            of: #"style\s*=\s*["'][^"']*["']"#,
            with: "",
            options: .regularExpression
        )

        // Convert markdown to plain text
        let lines = stripped.components(separatedBy: .newlines)
        var processedLines: [String] = []

        for line in lines {
            var processedLine = line

            // Remove markdown headers
            processedLine = processedLine.replacingOccurrences(
                of: #"^#+\s+"#,
                with: "",
                options: [.regularExpression, .anchored]
            )

            // Remove markdown bold
            processedLine = processedLine.replacingOccurrences(
                of: #"\*\*([^*]+)\*\*"#,
                with: "$1",
                options: .regularExpression
            )

            // Remove markdown italic
            processedLine = processedLine.replacingOccurrences(
                of: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#,
                with: "$1",
                options: .regularExpression
            )

            // Remove markdown inline code (keep the content)
            processedLine = processedLine.replacingOccurrences(
                of: #"`([^`]+)`"#,
                with: "$1",
                options: .regularExpression
            )

            processedLines.append(processedLine)
        }

        return processedLines.joined(separator: "\n")
    }

    func processContentForDisplay(content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var processedLines: [String] = []
        var skipTable = false
        var skipRationale = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip the main title (we already show it in the header)
            if index == 0 && (trimmed.hasPrefix("<h1>") || trimmed.hasPrefix("# ")) {
                continue
            }

            // Skip metadata section (we show this info in badges/configuration)
            if trimmed.contains("* **") || trimmed.hasPrefix("* **") {
                if trimmed.contains("default configuration:")
                    || trimmed.contains("Default configuration:") {
                    skipTable = true
                }
                continue
            }

            // Skip HTML table if we're in the metadata section
            if skipTable {
                if trimmed.hasPrefix("<table>") || trimmed.contains("<table>") {
                    continue
                } else if trimmed.hasPrefix("</table>") || trimmed.contains("</table>") {
                    skipTable = false
                    continue
                } else if trimmed.contains("<thead>") || trimmed.contains("</thead>") ||
                          trimmed.contains("<tbody>") || trimmed.contains("</tbody>") ||
                          trimmed.contains("<tr>") || trimmed.contains("</tr>") ||
                          trimmed.contains("<th>") || trimmed.contains("</th>") ||
                          trimmed.contains("<td>") || trimmed.contains("</td>") {
                    continue
                }
            }

            // Skip rationale/why section (shown separately in "Why This Matters")
            if trimmed.hasPrefix("##") {
                let heading = trimmed.lowercased()
                if heading.contains("rationale") || heading.contains("why") {
                    skipRationale = true
                    continue
                } else if skipRationale {
                    skipRationale = false
                }
            }
            if skipRationale {
                continue
            }

            // Add a blank line before "Non Triggering Examples" for visual separation
            if trimmed.hasPrefix("## Non") || trimmed.hasPrefix("## Non Triggering") {
                processedLines.append("")
            }

            processedLines.append(line)
        }

        return processedLines.joined(separator: "\n")
    }

    func convertMarkdownToHTML(content: String, colorScheme: ColorScheme? = nil) -> String {
        let lines = content.components(separatedBy: .newlines)
        var processedLines: [String] = []
        var inCodeBlock = false
        var codeBlockLanguage = ""

        for line in lines {
            let converted = convertMarkdownLine(
                line: line,
                inCodeBlock: &inCodeBlock,
                codeBlockLanguage: &codeBlockLanguage,
                colorScheme: colorScheme
            )
            processedLines.append(contentsOf: converted)
        }

        // Close any open code block
        if inCodeBlock {
            processedLines.append("</code></pre>")
        }

        return processedLines.joined(separator: "\n")
    }

    func wrapHTMLInDocument(body: String, colorScheme: ColorScheme) -> String {
        // Detect if we're in dark mode
        let isDarkMode = colorScheme == .dark

        let textColor = isDarkMode ? "#FFFFFF" : "#000000"
        let codeBgColor = isDarkMode ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.05)"
        let tableBorderColor = isDarkMode ? "rgba(255,255,255,0.2)" : "rgba(0,0,0,0.1)"
        let tableHeaderBg = isDarkMode ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.05)"

        let styles = htmlStyleBlock(
            textColor: textColor,
            codeBgColor: codeBgColor,
            tableBorderColor: tableBorderColor,
            tableHeaderBg: tableHeaderBg
        )

        // Use HTML fragment approach instead of full document to avoid document-level margins
        // Wrap in a div with inline styles - keep HTML compact to avoid whitespace rendering
        let divStyle = "font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; " +
            "font-size: 14px; line-height: 1.6; color: \(textColor); margin: 0; padding: 0;"
        return "<div style=\"\(divStyle)\"><style>\(styles)</style>\(body)</div>"
    }

    private func convertMarkdownLine(
        line: String,
        inCodeBlock: inout Bool,
        codeBlockLanguage: inout String,
        colorScheme: ColorScheme? = nil
    ) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Check if line already contains HTML tags - preserve it as-is
        let hasHTMLTags = trimmed.contains("<") && trimmed.contains(">")

        let monoFont = "'SF Mono', Monaco, 'Courier New', monospace"

        if line.hasPrefix("```") {
            if inCodeBlock {
                inCodeBlock = false
                codeBlockLanguage = ""
                return ["</code></pre>"]
            }

            let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            codeBlockLanguage = language.isEmpty ? "" : " class=\"language-\(language)\""
            inCodeBlock = true
            let fontStyle = "font-family: \(monoFont); font-size: 13px;"
            let openTag = "<pre style=\"\(fontStyle)\">" +
                "<code\(codeBlockLanguage) style=\"\(fontStyle)\">"
            return [openTag]
        }

        if inCodeBlock {
            let escaped = line
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return [highlightSwiftSyntax(in: escaped, colorScheme: colorScheme)]
        }

        if hasHTMLTags {
            return [line]
        }

        if line.hasPrefix("# ") {
            let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return ["<h1>\(text)</h1>"]
        }

        if line.hasPrefix("## ") {
            let text = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return ["<h2>\(text)</h2>"]
        }

        if line.hasPrefix("### ") {
            let text = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            return ["<h3>\(text)</h3>"]
        }

        if trimmed.isEmpty {
            return ["<br>"]
        }

        return [inlineMarkdownHTML(from: line)]
    }

    private func inlineMarkdownHTML(from line: String) -> String {
        var processedLine = line

        // Convert inline code (handle backticks) — use inline style because
        // NSAttributedString's HTML parser ignores <style> block selectors
        let inlineCodeStyle = "font-family: 'SF Mono', Monaco, 'Courier New', monospace; font-size: 13px;"
        processedLine = processedLine.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: "<code style=\"\(inlineCodeStyle)\">$1</code>",
            options: .regularExpression
        )

        // Convert bold
        processedLine = processedLine.replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )

        // Convert italic (but be careful not to match bold markers)
        processedLine = processedLine.replacingOccurrences(
            of: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )

        return processedLine
    }

    private func htmlStyleBlock(
        textColor: String,
        codeBgColor: String,
        tableBorderColor: String,
        tableHeaderBg: String
    ) -> String {
        htmlStyleTemplate
            .replacingOccurrences(of: "__TEXT_COLOR__", with: textColor)
            .replacingOccurrences(of: "__CODE_BG_COLOR__", with: codeBgColor)
            .replacingOccurrences(of: "__TABLE_BORDER__", with: tableBorderColor)
            .replacingOccurrences(of: "__TABLE_HEADER_BG__", with: tableHeaderBg)
    }

    private var htmlStyleTemplate: String {
        """
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            font-size: 14px;
            line-height: 1.6;
            color: __TEXT_COLOR__;
            margin: 0;
            padding: 0;
        }
        h1 {
            font-size: 14px;
            font-weight: 600;
            margin-top: 0;
            margin-bottom: 16px;
            color: __TEXT_COLOR__;
        }
        h2 {
            font-size: 14px;
            font-weight: 600;
            margin-top: 24px;
            margin-bottom: 12px;
            color: __TEXT_COLOR__;
        }
        h3 {
            font-size: 13px;
            font-weight: 600;
            margin-top: 20px;
            margin-bottom: 10px;
            color: __TEXT_COLOR__;
        }
        code {
            font-family: 'SF Mono', Monaco, 'Courier New', monospace;
            background-color: __CODE_BG_COLOR__;
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 13px;
            color: __TEXT_COLOR__;
        }
        pre {
            background-color: __CODE_BG_COLOR__;
            padding: 8px;
            border-radius: 6px;
            overflow-x: auto;
            margin: 8px 0;
        }
        pre code {
            background: none;
            padding: 0;
            color: __TEXT_COLOR__;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 12px 0;
        }
        th, td {
            border: 1px solid __TABLE_BORDER__;
            padding: 8px 12px;
            text-align: left;
            color: __TEXT_COLOR__;
        }
        th {
            background-color: __TABLE_HEADER_BG__;
            font-weight: 600;
        }
        p {
            margin: 8px 0;
            color: __TEXT_COLOR__;
        }
        ul, ol {
            margin: 8px 0;
            padding-left: 20px;
            color: __TEXT_COLOR__;
        }
        li {
            margin: 4px 0;
            color: __TEXT_COLOR__;
        }
        strong {
            color: __TEXT_COLOR__;
        }
        em {
            color: __TEXT_COLOR__;
        }
        """
    }
}
