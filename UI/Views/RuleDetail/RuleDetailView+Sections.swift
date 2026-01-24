import SwiftUI

extension RuleDetailView {
    /// Determines if the short description should be shown (only if it's unique and not in markdown)
    var shouldShowShortDescription: Bool {
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
    
    var headerView: some View {
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
    
    var descriptionView: some View {
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
    
    var configurationView: some View {
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
    
    var examplesView: some View {
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
    
    func documentationView(markdown: String, colorScheme: ColorScheme) -> some View {
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
    
    var whyThisMattersView: some View {
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
    
    var violationsCountView: some View {
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
    
    var relatedRulesView: some View {
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
    
    var swiftEvolutionView: some View {
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
}
