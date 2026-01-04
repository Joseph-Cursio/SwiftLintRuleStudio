//
//  RuleBrowserView.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI

struct RuleBrowserView: View {
    @EnvironmentObject var ruleRegistry: RuleRegistry
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: RuleBrowserViewModel
    @State private var selectedRuleId: String?
    
    init() {
        // Create a temporary ruleRegistry for initialization
        // Will be updated in onAppear with the actual one from environment
        let tempRegistry = RuleRegistry(
            swiftLintCLI: SwiftLintCLI(cacheManager: CacheManager()),
            cacheManager: CacheManager()
        )
        _viewModel = StateObject(wrappedValue: RuleBrowserViewModel(ruleRegistry: tempRegistry))
    }
    
    var body: some View {
        NavigationSplitView {
            // First panel: Rule List
            ruleListView
                .navigationSplitViewColumnWidth(min: 200, ideal: 300)
        } detail: {
            Group {
                // Second panel: Rule Detail (only shown when rule is selected)
                if let selectedRuleId = selectedRuleId,
                   let selectedRule = ruleRegistry.rules.first(where: { $0.id == selectedRuleId }) {
                    RuleDetailView(rule: selectedRule)
                        .id(selectedRuleId) // Force view recreation when selection changes
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(.leading, -16) // Negative padding to counteract NavigationSplitView default padding
                } else {
                    // Empty view - no message shown
                    Color.clear
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 500)
        }
        .navigationTitle("Rules")
        .onAppear {
            // Update viewModel with the actual ruleRegistry from environment
            viewModel.ruleRegistry = ruleRegistry
        }
        .onChange(of: viewModel.filteredRules) {
            // Clear selection if the selected rule is no longer in the filtered list
            if let selectedRuleId = selectedRuleId,
               !viewModel.filteredRules.contains(where: { $0.id == selectedRuleId }) {
                self.selectedRuleId = nil
            }
        }
    }
    
    private var ruleListView: some View {
        VStack(spacing: 0) {
            // Search and Filters
            searchAndFiltersView
            
            Divider()
            
            // Rules List
            if viewModel.filteredRules.isEmpty {
                emptyStateView
            } else {
                List(selection: $selectedRuleId) {
                    ForEach(viewModel.filteredRules, id: \.id) { rule in
                        RuleListItem(rule: rule)
                            .tag(rule.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.clearFilters()
                } label: {
                    Label("Clear Filters", systemImage: "xmark.circle")
                }
                .disabled(viewModel.searchText.isEmpty && viewModel.selectedCategory == nil && viewModel.selectedStatus == .all)
            }
        }
    }
    
    private var searchAndFiltersView: some View {
        VStack(spacing: 12) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search rules...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Status Filter
                    Picker("Status", selection: $viewModel.selectedStatus) {
                        ForEach(RuleStatusFilter.allCases) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    
                    // Category Filter
                    Picker("Category", selection: $viewModel.selectedCategory) {
                        Text("All Categories").tag(nil as RuleCategory?)
                        ForEach(RuleCategory.allCases) { category in
                            HStack {
                                Text(category.displayName)
                                if let count = viewModel.categoryCounts[category] {
                                    Text("(\(count))")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                            .tag(category as RuleCategory?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                    
                    // Sort Option
                    Picker("Sort", selection: $viewModel.selectedSortOption) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 8)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No rules found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if !viewModel.searchText.isEmpty || viewModel.selectedCategory != nil || viewModel.selectedStatus != .all {
                Text("Try adjusting your filters")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button("Clear Filters") {
                    viewModel.clearFilters()
                }
                .buttonStyle(.bordered)
            } else if ruleRegistry.rules.isEmpty {
                Text("Loading rules...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    @ViewBuilder
    private func documentationTextView(markdown: String, colorScheme: ColorScheme) -> some View {
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
    
    private func convertMarkdownToPlainText(content: String) -> String {
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
    
    private func stripHTMLTags(from text: String) -> String {
        // Remove all HTML tags except markdown code blocks
        var result = text
        var inCodeBlock = false
        var codeBlockContent: [String] = []
        var lines = text.components(separatedBy: .newlines)
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
    
    private func processContentForDisplay(content: String) -> String {
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
    
    private func convertMarkdownToHTML(content: String) -> String {
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
    
    private func wrapHTMLInDocument(body: String, colorScheme: ColorScheme) -> String {
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

#Preview {
    let cacheManager = CacheManager()
    let swiftLintCLI = SwiftLintCLI(cacheManager: CacheManager())
    let ruleRegistry = RuleRegistry(swiftLintCLI: swiftLintCLI, cacheManager: cacheManager)
    let container = DependencyContainer(
        ruleRegistry: ruleRegistry,
        swiftLintCLI: swiftLintCLI,
        cacheManager: cacheManager
    )
    
    RuleBrowserView()
        .environmentObject(ruleRegistry)
        .environmentObject(container)
}

