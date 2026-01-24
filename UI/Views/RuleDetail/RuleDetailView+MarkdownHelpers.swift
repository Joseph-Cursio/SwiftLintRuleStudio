import SwiftUI

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
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip the main title (we already show it in the header)
            if index == 0 && (trimmed.hasPrefix("<h1>") || trimmed.hasPrefix("# ")) {
                continue
            }
            
            // Skip metadata section (we show this info in badges/configuration)
            if trimmed.contains("* **") || trimmed.hasPrefix("* **") {
                // Check if this is the default configuration line
                if trimmed.contains("default configuration:") || trimmed.contains("Default configuration:") {
                    // Skip the HTML table that follows
                    skipTable = true
                }
                continue
            }
            
            // Skip HTML table if we're in the metadata section
            if skipTable {
                if trimmed.hasPrefix("<table>") || trimmed.contains("<table>") {
                    // Skip until we find </table>
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
            let converted = convertMarkdownLine(
                line: line,
                inCodeBlock: &inCodeBlock,
                codeBlockLanguage: &codeBlockLanguage
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
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
            \(styles)
            </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
    
    private func convertMarkdownLine(
        line: String,
        inCodeBlock: inout Bool,
        codeBlockLanguage: inout String
    ) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Check if line already contains HTML tags - preserve it as-is
        let hasHTMLTags = trimmed.contains("<") && trimmed.contains(">")
        
        if line.hasPrefix("```") {
            if inCodeBlock {
                inCodeBlock = false
                codeBlockLanguage = ""
                return ["</code></pre>"]
            }
            
            let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            codeBlockLanguage = language.isEmpty ? "" : " class=\"language-\(language)\""
            inCodeBlock = true
            return ["<pre><code\(codeBlockLanguage)>"]
        }
        
        if inCodeBlock {
            let escaped = line
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return [escaped]
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
        
        // Convert inline code (handle backticks)
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
        """
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            font-size: 14px;
            line-height: 1.6;
            color: \(textColor);
            margin: 0;
            padding: 0;
        }
        h1 {
            font-size: 20px;
            font-weight: 600;
            margin-top: 0;
            margin-bottom: 16px;
            color: \(textColor);
        }
        h2 {
            font-size: 18px;
            font-weight: 600;
            margin-top: 24px;
            margin-bottom: 12px;
            color: \(textColor);
        }
        h3 {
            font-size: 16px;
            font-weight: 600;
            margin-top: 20px;
            margin-bottom: 10px;
            color: \(textColor);
        }
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
        pre code {
            background: none;
            padding: 0;
            color: \(textColor);
        }
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 12px 0;
        }
        th, td {
            border: 1px solid \(tableBorderColor);
            padding: 8px 12px;
            text-align: left;
            color: \(textColor);
        }
        th {
            background-color: \(tableHeaderBg);
            font-weight: 600;
        }
        p {
            margin: 8px 0;
            color: \(textColor);
        }
        ul, ol {
            margin: 8px 0;
            padding-left: 24px;
            color: \(textColor);
        }
        li {
            margin: 4px 0;
            color: \(textColor);
        }
        strong {
            color: \(textColor);
        }
        em {
            color: \(textColor);
        }
        """
    }
}
