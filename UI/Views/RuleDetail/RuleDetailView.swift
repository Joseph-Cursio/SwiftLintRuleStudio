//
//  RuleDetailView.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import SwiftUI

struct RuleDetailView: View {
    @StateObject private var viewModel: RuleDetailViewModel
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var dependencies: DependencyContainer
    @State private var showSaveConfirmation = false
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var showImpactSimulation = false
    @State private var impactResult: RuleImpactResult?
    @State private var isSimulating = false
    @State private var currentRule: Rule
    @State private var violationCount: Int = 0
    @State private var isLoadingViolationCount = false
    
    let ruleId: String
    
    // Get the latest rule from registry (may have updated documentation)
    // Made internal for testing
    var rule: Rule {
        dependencies.ruleRegistry.getRule(id: ruleId) ?? currentRule
    }
    
    init(rule: Rule) {
        self.ruleId = rule.id
        _currentRule = State(initialValue: rule)
        // Create ViewModel - will be updated with workspace config in onAppear
        _viewModel = StateObject(wrappedValue: RuleDetailViewModel(rule: rule))
    }

    init(rule: Rule, viewModel: RuleDetailViewModel) {
        self.ruleId = rule.id
        _currentRule = State(initialValue: rule)
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerView
                
                Divider()
                
                // Configuration
                configurationView
                
                Divider()
                
                // Description
                descriptionView
                
                Divider()
                
                // Why This Matters (Rationale)
                whyThisMattersView
                
                Divider()
                
                // Violations Count
                violationsCountView
                
                Divider()
                
                // Related Rules
                relatedRulesView
                
                Divider()
                
                // Swift Evolution Links
                swiftEvolutionView
            }
            .padding(.top, 8) // Minimal top padding
            .padding(.bottom)
            .padding(.trailing)
            .padding(.leading, 0) // No left padding - NavigationSplitView may add its own
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationTitle(rule.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.pendingChanges != nil {
                    Button {
                        viewModel.showPreview()
                    } label: {
                        Label("Preview Changes", systemImage: "eye")
                    }
                    
                    Button {
                        Task {
                            do {
                                try viewModel.saveConfiguration()
                                showSaveConfirmation = true
                            } catch {
                                showError = true
                            }
                        }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Label("Save", systemImage: "checkmark")
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
                
                Toggle("Enabled", isOn: Binding(
                    get: { viewModel.isEnabled },
                    set: { viewModel.updateEnabled($0) }
                ))
                .toggleStyle(.switch)
            }
        }
        .onAppear {
            // Update ViewModel with workspace config if available
            if let workspace = dependencies.workspaceManager.currentWorkspace,
               let configPath = workspace.configPath {
                let yamlEngine = YAMLConfigurationEngine(configPath: configPath)
                viewModel.yamlEngine = yamlEngine
                viewModel.workspaceManager = dependencies.workspaceManager
                
                // Load current configuration
                do {
                    try viewModel.loadConfiguration()
                } catch {
                    print("Warning: Failed to load configuration: \(error)")
                }
            }
            
            // Fetch rule details if documentation is missing
            if rule.markdownDocumentation == nil || rule.markdownDocumentation?.isEmpty == true {
                Task {
                    await dependencies.ruleRegistry.fetchRuleDetailsIfNeeded(id: ruleId)
                    // Update local state when rule is updated
                    if let updatedRule = dependencies.ruleRegistry.getRule(id: ruleId) {
                        await MainActor.run {
                            currentRule = updatedRule
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ruleConfigurationDidChange)) { notification in
            // Reload configuration if this rule was changed
            if let ruleId = notification.userInfo?["ruleId"] as? String,
               ruleId == rule.id {
                try? viewModel.loadConfiguration()
            }
        }
        .id(rule.id) // Force view recreation when rule ID changes
        .onChange(of: dependencies.ruleRegistry.rules) {
            // Update local rule when registry updates
            if let updatedRule = dependencies.ruleRegistry.getRule(id: ruleId) {
                currentRule = updatedRule
            }
        }
        .sheet(isPresented: $viewModel.showDiffPreview) {
            if let diff = viewModel.generateDiff() {
                ConfigDiffPreviewView(diff: diff, ruleName: rule.name) {
                    Task {
                        do {
                            try viewModel.saveConfiguration()
                            viewModel.showDiffPreview = false
                            showSaveConfirmation = true
                        } catch {
                            showError = true
                        }
                    }
                } onCancel: {
                    viewModel.showDiffPreview = false
                }
            }
        }
        .alert("Configuration Saved", isPresented: $showSaveConfirmation) {
            Button("OK") { }
        } message: {
            Text("Rule configuration has been saved to your workspace's .swiftlint.yml file.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                viewModel.saveError = nil
            }
        } message: {
            Text(viewModel.saveError?.localizedDescription ?? "An error occurred while saving the configuration.")
        }
        .sheet(isPresented: $showImpactSimulation) {
            if let result = impactResult {
                ImpactSimulationView(
                    ruleId: rule.id,
                    ruleName: rule.name,
                    result: result,
                    onEnable: {
                        viewModel.updateEnabled(true)
                    }
                )
            }
        }
    }
    
    private func simulateRule() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else {
            return
        }
        
        isSimulating = true
        
        Task {
            do {
                let result = try await dependencies.impactSimulator.simulateRule(
                    ruleId: rule.id,
                    workspace: workspace,
                    baseConfigPath: workspace.configPath
                )
                
                await MainActor.run {
                    impactResult = result
                    isSimulating = false
                    showImpactSimulation = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isSimulating = false
                }
            }
        }
    }
    
    /// Determines if the short description should be shown (only if it's unique and not in markdown)
    private var shouldShowShortDescription: Bool {
        guard !rule.description.isEmpty && rule.description != "No description available" else {
            return false
        }
        // If we have markdown, check if the short description is already contained in it
        if let markdownDoc = rule.markdownDocumentation, !markdownDoc.isEmpty {
            // Check if the description text appears in the markdown (case-insensitive, ignoring whitespace)
            let normalizedDescription = rule.description.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedMarkdown = markdownDoc
                .lowercased()
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
            // Only show short description if it's NOT found in the markdown
            return !normalizedMarkdown.contains(normalizedDescription)
        }
        // If no markdown, show the short description
        return true
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(rule.id)
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                CategoryBadge(category: rule.category)
                    .scaleEffect(1.2)
            }
            
            HStack(spacing: 16) {
                if rule.isOptIn {
                    Label("Opt-In Rule", systemImage: "star.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
                
                if viewModel.isEnabled {
                    Label("Enabled", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                
                if rule.supportsAutocorrection {
                    Label("Auto-correctable", systemImage: "wand.and.stars")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                
                if let minVersion = rule.minimumSwiftVersion {
                    Label("Swift \(minVersion)+", systemImage: "swift")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var descriptionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
            
            // Only show the short description if it's unique (not already in markdown)
            if shouldShowShortDescription {
                Text(rule.description)
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            // Show markdown documentation if available - directly below description
            if let markdownDoc = rule.markdownDocumentation, !markdownDoc.isEmpty {
                // Process content to remove metadata we already show
                let processedContent = processContentForDisplay(content: markdownDoc)
                
                // Convert markdown elements to HTML while preserving existing HTML
                let htmlContent = convertMarkdownToHTML(content: processedContent)
                
                // Wrap in full HTML document with styling
                let fullHTML = wrapHTMLInDocument(body: htmlContent, colorScheme: colorScheme)
                
                // Determine top padding: only add spacing if we showed the short description above
                let hasShortDescription = shouldShowShortDescription
                
                // Render HTML using NSAttributedString
                if let htmlData = fullHTML.data(using: .utf8),
                   let attributedString = try? NSAttributedString(
                    data: htmlData,
                    options: [.documentType: NSAttributedString.DocumentType.html,
                             .characterEncoding: String.Encoding.utf8.rawValue],
                    documentAttributes: nil
                   ) {
                    Text(AttributedString(attributedString))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, hasShortDescription ? 8 : 0)
                } else {
                    // Fallback to plain text if HTML parsing fails
                    Text(processedContent)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, hasShortDescription ? 8 : 0)
                }
            } else if rule.description.isEmpty || rule.description == "No description available" {
                // Show message if we have neither description nor markdown documentation
                Text("No description available")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
    
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
    
    private var configurationView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable this rule", isOn: Binding(
                    get: { viewModel.isEnabled },
                    set: { viewModel.updateEnabled($0) }
                ))
                
                if viewModel.isEnabled {
                    Picker("Severity", selection: Binding(
                        get: { viewModel.severity ?? .warning },
                        set: { viewModel.updateSeverity($0) }
                    )) {
                        ForEach(Severity.allCases) { severity in
                            Text(severity.displayName).tag(severity)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                
                if viewModel.pendingChanges != nil {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                            .accessibilityHidden(true)
                        Text("You have unsaved changes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
                
                // Simulate button for disabled rules
                if !viewModel.isEnabled,
                   dependencies.workspaceManager.currentWorkspace != nil {
                    Divider()
                    
                    Button {
                        simulateRule()
                    } label: {
                        HStack {
                            if isSimulating {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "chart.bar.fill")
                                    .accessibilityHidden(true)
                            }
                            Text("Simulate Impact")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSimulating)
                }
            }
            .padding(.vertical)
            .padding(.trailing)
            .padding(.leading, 0) // No left padding
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private var examplesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Examples")
                .font(.headline)
            
            if !rule.triggeringExamples.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Triggering Examples", systemImage: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.red)
                    
                    ForEach(Array(rule.triggeringExamples.enumerated()), id: \.offset) { _, example in
                        CodeBlock(code: example, isError: true)
                    }
                }
            }
            
            if !rule.nonTriggeringExamples.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Non-Triggering Examples", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                    
                    ForEach(Array(rule.nonTriggeringExamples.enumerated()), id: \.offset) { _, example in
                        CodeBlock(code: example, isError: false)
                    }
                }
            }
            
            if rule.triggeringExamples.isEmpty && rule.nonTriggeringExamples.isEmpty {
                Text("No examples available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
    
    private func documentationView(markdown: String, colorScheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Documentation")
                .font(.headline)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Process content to remove metadata we already show
                    let processedContent = processContentForDisplay(content: markdown)
                    
                    // Convert markdown elements to HTML while preserving existing HTML
                    let htmlContent = convertMarkdownToHTML(content: processedContent)
                    
                    // Wrap in full HTML document with styling
                    let fullHTML = wrapHTMLInDocument(body: htmlContent, colorScheme: colorScheme)
                    
                    // Render HTML using NSAttributedString
                    if let htmlData = fullHTML.data(using: .utf8),
                       let attributedString = try? NSAttributedString(
                        data: htmlData,
                        options: [.documentType: NSAttributedString.DocumentType.html,
                                 .characterEncoding: String.Encoding.utf8.rawValue],
                        documentAttributes: nil
                       ) {
                        Text(AttributedString(attributedString))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        // Fallback to plain text if HTML parsing fails
                        Text(processedContent)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical)
                .padding(.trailing)
                .padding(.leading, 0) // No left padding
            }
            .frame(maxHeight: 500)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private func processContentForDisplay(content: String) -> String {
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
    
    private func convertMarkdownToHTML(content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var processedLines: [String] = []
        var inCodeBlock = false
        var codeBlockLanguage = ""
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check if line already contains HTML tags - preserve it as-is
            let hasHTMLTags = trimmed.contains("<") && trimmed.contains(">")
            
            // Handle markdown code blocks
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    processedLines.append("</code></pre>")
                    inCodeBlock = false
                    codeBlockLanguage = ""
                } else {
                    // Start code block
                    let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeBlockLanguage = language.isEmpty ? "" : " class=\"language-\(language)\""
                    processedLines.append("<pre><code\(codeBlockLanguage)>")
                    inCodeBlock = true
                }
                continue
            }
            
            if inCodeBlock {
                // Escape HTML in code blocks
                let escaped = line
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                processedLines.append(escaped)
                continue
            }
            
            // If line already has HTML tags, preserve it as-is
            // (HTML content should already be properly formatted)
            if hasHTMLTags {
                processedLines.append(line)
                continue
            }
            
            // Convert markdown headers (only if not already HTML)
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
                // Regular line - convert inline markdown
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
                
                processedLines.append(processedLine)
            }
        }
        
        // Close any open code block
        if inCodeBlock {
            processedLines.append("</code></pre>")
        }
        
        return processedLines.joined(separator: "\n")
    }
    
    private func wrapHTMLInDocument(body: String, colorScheme: ColorScheme) -> String {
        // Detect if we're in dark mode
        let isDarkMode = colorScheme == .dark
        
        let textColor = isDarkMode ? "#FFFFFF" : "#000000"
        let codeBgColor = isDarkMode ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.05)"
        let tableBorderColor = isDarkMode ? "rgba(255,255,255,0.2)" : "rgba(0,0,0,0.1)"
        let tableHeaderBg = isDarkMode ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.05)"
        
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
            </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
    
    // MARK: - New Sections
    
    private var whyThisMattersView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why This Matters")
                .font(.headline)
            
            if let rationale = extractRationale(from: rule.markdownDocumentation ?? "") {
                Text(rationale)
                    .font(.body)
                    .foregroundColor(.primary)
            } else {
                Text("No rationale available")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
    
    private var violationsCountView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Violations")
                .font(.headline)
            
            if isLoadingViolationCount {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                HStack(spacing: 8) {
                    Text("\(violationCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(violationCount > 0 ? .orange : .green)
                    
                    Text(violationCount == 1 ? "violation" : "violations")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    if violationCount > 0 {
                        Text("in current workspace")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var relatedRulesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Related Rules")
                .font(.headline)
            
            let related = relatedRules
            if related.isEmpty {
                Text("No related rules found")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(related.prefix(5), id: \.id) { relatedRule in
                        Button {
                            // Navigate to related rule - would need navigation handling
                        } label: {
                            HStack {
                                Text(relatedRule.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if related.count > 5 {
                        Text("+ \(related.count - 5) more")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
        }
    }
    
    private var swiftEvolutionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Swift Evolution")
                .font(.headline)
            
            let links = extractSwiftEvolutionLinks(from: rule.markdownDocumentation ?? "")
            if links.isEmpty {
                Text("No Swift Evolution proposals linked")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(links, id: \.self) { link in
                        Link(destination: link) {
                            HStack {
                                Image(systemName: "link")
                                    .font(.caption)
                                    .accessibilityHidden(true)
                                Text(link.absoluteString)
                                    .font(.body)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var relatedRules: [Rule] {
        dependencies.ruleRegistry.rules
            .filter { $0.id != rule.id && $0.category == rule.category }
            .sorted { $0.name < $1.name }
    }
    
    private func extractRationale(from markdown: String) -> String? {
        guard !markdown.isEmpty else { return nil }
        
        let lines = markdown.components(separatedBy: .newlines)
        var inRationaleSection = false
        var rationaleLines: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Look for "## Rationale" or "## Why" section
            if trimmed.hasPrefix("##") {
                let sectionName = trimmed.lowercased()
                if sectionName.contains("rationale") || sectionName.contains("why") {
                    inRationaleSection = true
                    continue
                } else if inRationaleSection {
                    // Hit another section, stop collecting
                    break
                }
            }
            
            if inRationaleSection {
                // Skip code blocks
                if trimmed.hasPrefix("```") {
                    continue
                }
                
                // Skip empty lines at start
                if rationaleLines.isEmpty && trimmed.isEmpty {
                    continue
                }
                
                // Collect rationale text (stop at code blocks or next major section)
                if !trimmed.isEmpty {
                    rationaleLines.append(trimmed)
                } else if !rationaleLines.isEmpty {
                    // Empty line after content - we have enough
                    break
                }
            }
        }
        
        if !rationaleLines.isEmpty {
            return rationaleLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    private func extractSwiftEvolutionLinks(from markdown: String) -> [URL] {
        guard !markdown.isEmpty else { return [] }
        
        var links: [URL] = []
        
        // Look for Swift Evolution URLs
        let patterns = [
            #"https?://github\.com/apple/swift-evolution/blob/.*SE-\d+"#,
            #"https?://github\.com/apple/swift-evolution/.*SE-\d+"#,
            #"SE-\d+"#,
            #"swift-evolution.*SE-\d+"#
        ]
        
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
            
            regex?.enumerateMatches(in: markdown, options: [], range: range) { match, _, _ in
                guard let match = match,
                      let range = Range(match.range, in: markdown) else { return }
                
                let matchedString = String(markdown[range])
                
                // Convert to full URL if needed
                if matchedString.hasPrefix("http") {
                    if let url = URL(string: matchedString) {
                        links.append(url)
                    }
                } else if matchedString.contains("SE-") {
                    // Extract SE number and construct URL
                    if let seNumber = matchedString.components(separatedBy: CharacterSet.decimalDigits.inverted)
                        .joined().components(separatedBy: "SE").last,
                       !seNumber.isEmpty {
                        let urlString = "https://github.com/apple/swift-evolution/blob/main/proposals/\(seNumber.prefix(4)).md"
                        if let url = URL(string: urlString) {
                            links.append(url)
                        }
                    }
                }
            }
        }
        
        return Array(Set(links)).sorted { $0.absoluteString < $1.absoluteString }
    }
    
    private func loadViolationCount() {
        guard let workspace = dependencies.workspaceManager.currentWorkspace else {
            violationCount = 0
            return
        }
        
        isLoadingViolationCount = true
        
        Task {
            do {
                let filter = ViolationFilter(ruleIDs: [rule.id], suppressedOnly: false)
                let count = try await dependencies.violationStorage.getViolationCount(
                    filter: filter,
                    workspaceId: workspace.id
                )
                
                await MainActor.run {
                    violationCount = count
                    isLoadingViolationCount = false
                }
            } catch {
                await MainActor.run {
                    violationCount = 0
                    isLoadingViolationCount = false
                }
            }
        }
    }
}

#if DEBUG
extension RuleDetailView {
    @MainActor static func extractRationaleForTesting(_ markdown: String) -> String? {
        let rule = Rule(
            id: "test_rule",
            name: "Test Rule",
            description: "Test description",
            category: .lint,
            isOptIn: false,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: false,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: markdown
        )
        return RuleDetailView(rule: rule).extractRationale(from: markdown)
    }

    @MainActor static func extractSwiftEvolutionLinksForTesting(_ markdown: String) -> [URL] {
        let rule = Rule(
            id: "test_rule",
            name: "Test Rule",
            description: "Test description",
            category: .lint,
            isOptIn: false,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: false,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: markdown
        )
        return RuleDetailView(rule: rule).extractSwiftEvolutionLinks(from: markdown)
    }

    @MainActor static func processContentForDisplayForTesting(_ content: String) -> String {
        let rule = Rule(
            id: "test_rule",
            name: "Test Rule",
            description: "Test description",
            category: .lint,
            isOptIn: false,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: false,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: content
        )
        return RuleDetailView(rule: rule).processContentForDisplay(content: content)
    }

    @MainActor static func convertMarkdownToHTMLForTesting(_ content: String) -> String {
        let rule = Rule(
            id: "test_rule",
            name: "Test Rule",
            description: "Test description",
            category: .lint,
            isOptIn: false,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: false,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: content
        )
        return RuleDetailView(rule: rule).convertMarkdownToHTML(content: content)
    }

    @MainActor static func wrapHTMLInDocumentForTesting(body: String, colorScheme: ColorScheme) -> String {
        let rule = Rule(
            id: "test_rule",
            name: "Test Rule",
            description: "Test description",
            category: .lint,
            isOptIn: false,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: false,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: nil
        )
        return RuleDetailView(rule: rule).wrapHTMLInDocument(body: body, colorScheme: colorScheme)
    }
}
#endif

struct CodeBlock: View {
    let code: String
    let isError: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(isError ? Color.red : Color.green)
                .frame(width: 4)
            
            Text(code)
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.textBackgroundColor))
        }
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isError ? Color.red.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    let rule = Rule(
        id: "force_cast",
        name: "Force Cast",
        description: "Force casts should be avoided. Use optional binding or guard statements instead.",
        category: .lint,
        isOptIn: false,
        severity: .error,
        parameters: nil,
        triggeringExamples: [
            "let string = value as! String",
            "let number = data as! Int"
        ],
        nonTriggeringExamples: [
            "if let string = value as? String { }",
            "guard let number = data as? Int else { return }"
        ],
        documentation: nil,
        isEnabled: true,
        supportsAutocorrection: false,
        minimumSwiftVersion: "5.0.0",
        defaultSeverity: .error,
        markdownDocumentation: nil
    )
    
    NavigationStack {
        RuleDetailView(rule: rule)
    }
    .frame(width: 800, height: 600)
}

