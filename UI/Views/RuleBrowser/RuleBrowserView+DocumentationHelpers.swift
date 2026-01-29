import SwiftUI

// swiftlint:disable function_body_length

extension RuleBrowserView {
    @ViewBuilder
    func documentationTextView(markdown: String, colorScheme: ColorScheme) -> some View {
        // Strip all HTML and render as plain text to avoid any layout issues
        let strippedContent = stripHTMLTags(from: markdown)
        let processedContent = processContentForDisplay(content: strippedContent)
        // Convert markdown to plain text (remove markdown syntax)
        let plainText = convertMarkdownToPlainText(content: processedContent)

        Text(plainText)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }

    func convertMarkdownToPlainText(content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
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

    func stripHTMLTags(from text: String) -> String {
        // Remove all HTML tags except markdown code blocks
        var inCodeBlock = false
        let lines = text.components(separatedBy: .newlines)
        var processedLines: [String] = []

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeBlock.toggle()
                processedLines.append(line)
                continue
            }

            if inCodeBlock {
                processedLines.append(line)
            } else {
                // Remove HTML tags and inline styles from non-code lines
                var cleanedLine = line
                // First remove inline styles (style="...")
                cleanedLine = cleanedLine.replacingOccurrences(
                    of: #"style\s*=\s*["'][^"']*["']"#,
                    with: "",
                    options: .regularExpression
                )
                // Then remove all HTML tags
                cleanedLine = cleanedLine.replacingOccurrences(
                    of: #"<[^>]+>"#,
                    with: "",
                    options: .regularExpression
                )
                processedLines.append(cleanedLine)
            }
        }

        return processedLines.joined(separator: "\n")
    }

    func processContentForDisplay(content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var processedLines: [String] = []
        var skipTable = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip the main title
            if index == 0 && (trimmed.hasPrefix("<h1>") || trimmed.hasPrefix("# ")) {
                continue
            }

            // Skip metadata section
            if trimmed.contains("* **") || trimmed.hasPrefix("* **") {
                if trimmed.contains("default configuration:") || trimmed.contains("Default configuration:") {
                    skipTable = true
                }
                continue
            }

            // Skip ALL HTML tables (not just metadata section)
            if trimmed.hasPrefix("<table") || trimmed.contains("<table>") || trimmed.contains("<table ") {
                skipTable = true
                continue
            }
            if skipTable {
                if trimmed.hasPrefix("</table>") || trimmed.contains("</table>") {
                    skipTable = false
                    continue
                } else if trimmed.contains("<thead>") || trimmed.contains("</thead>") ||
                            trimmed.contains("<tbody>") || trimmed.contains("</tbody>") ||
                            trimmed.contains("<tr>") || trimmed.contains("</tr>") ||
                            trimmed.contains("<th>") || trimmed.contains("</th>") ||
                            trimmed.contains("<td>") || trimmed.contains("</td>") ||
                            trimmed.contains("<thead") || trimmed.contains("<tbody") ||
                            trimmed.contains("<tr") || trimmed.contains("<th") ||
                            trimmed.contains("<td") {
                    continue
                }
            }

            // Skip horizontal rules (dividers)
            if trimmed.hasPrefix("<hr") || trimmed.contains("<hr>") ||
                trimmed.hasPrefix("---") || trimmed == "---" {
                continue
            }

            processedLines.append(line)
        }

        return processedLines.joined(separator: "\n")
    }

    func convertMarkdownToHTML(content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var processedLines: [String] = []
        var inCodeBlock = false
        var codeBlockLanguage = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let hasHTMLTags = trimmed.contains("<") && trimmed.contains(">")

            // Handle markdown code blocks
            if line.hasPrefix("```") {
                if inCodeBlock {
                    processedLines.append("</code></pre>")
                    inCodeBlock = false
                    codeBlockLanguage = ""
                } else {
                    let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeBlockLanguage = language.isEmpty ? "" : " class=\"language-\(language)\""
                    processedLines.append("<pre><code\(codeBlockLanguage)>")
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                let escaped = line
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                processedLines.append(escaped)
                continue
            }

            if hasHTMLTags {
                processedLines.append(line)
                continue
            }

            // Convert markdown headers
            if line.hasPrefix("# ") {
                let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                processedLines.append("<h1>\(text)</h1>")
            } else if line.hasPrefix("## ") {
                let text = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                processedLines.append("<h2>\(text)</h2>")
            } else if line.hasPrefix("### ") {
                let text = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                processedLines.append("<h3>\(text)</h3>")
            } else if trimmed.isEmpty {
                processedLines.append("<br>")
            } else {
                var processedLine = line

                // Convert inline code
                processedLine = processedLine.replacingOccurrences(
                    of: #"`([^`]+)`"#,
                    with: "<code>$1</code>",
                    options: .regularExpression
                )

                // Convert bold
                processedLine = processedLine.replacingOccurrences(
                    of: #"\*\*([^*]+)\*\*"#,
                    with: "<strong>$1</strong>",
                    options: .regularExpression
                )

                // Convert italic
                processedLine = processedLine.replacingOccurrences(
                    of: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#,
                    with: "<em>$1</em>",
                    options: .regularExpression
                )

                processedLines.append(processedLine)
            }
        }

        if inCodeBlock {
            processedLines.append("</code></pre>")
        }

        return processedLines.joined(separator: "\n")
    }

    func wrapHTMLInDocument(body: String, colorScheme: ColorScheme) -> String {
        let isDarkMode = colorScheme == .dark
        let textColor = isDarkMode ? "#FFFFFF" : "#000000"
        let codeBgColor = isDarkMode ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.05)"

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                    font-size: 14px;
                    line-height: 1.6;
                    color: \(textColor);
                    margin: 0;
                    padding: 0;
                    display: block !important;
                    width: 100% !important;
                }
                h1 { font-size: 20px; font-weight: 600; margin-top: 0; margin-bottom: 16px; color: \(textColor); }
                h2 { font-size: 18px; font-weight: 600; margin-top: 24px; margin-bottom: 12px; color: \(textColor); }
                h3 { font-size: 16px; font-weight: 600; margin-top: 20px; margin-bottom: 10px; color: \(textColor); }
                code {
                    font-family: 'SF Mono', Monaco, 'Courier New', monospace;
                    background-color: \(codeBgColor);
                    padding: 2px 6px;
                    border-radius: 3px;
                    font-size: 13px;
                    color: \(textColor);
                }
                pre {
                    background-color: \(codeBgColor);
                    padding: 12px;
                    border-radius: 6px;
                    overflow-x: auto;
                    margin: 12px 0;
                }
                pre code { background: none; padding: 0; color: \(textColor); }
                p { margin: 8px 0; color: \(textColor); }
                ul, ol { margin: 8px 0; padding-left: 24px; color: \(textColor); list-style-position: inside; }
                li { margin: 4px 0; color: \(textColor); display: list-item; }
                strong { color: \(textColor); }
                em { color: \(textColor); }
                hr { display: none; }
                table { border: none; border-collapse: collapse; width: 100%; display: block; }
                td, th { border: none; display: block; width: 100%; padding: 4px; }
                tr { display: block; width: 100%; }
                thead, tbody { display: block; width: 100%; }
                div { display: block; width: 100%; }
                * {
                    max-width: 100% !important;
                    box-sizing: border-box !important;
                    float: none !important;
                    display: block !important;
                    width: 100% !important;
                }
                p, span, div, section, article {
                    display: block !important;
                    width: 100% !important;
                    float: none !important;
                }
            </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}
// swiftlint:enable function_body_length
