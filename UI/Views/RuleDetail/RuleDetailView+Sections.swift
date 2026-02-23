// swiftlint:disable file_length
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
            let normalizedDescription = rule.description
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
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
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                CategoryBadge(category: rule.category)
                    .scaleEffect(1.2)
            }
            
            HStack(spacing: 16) {
                if rule.isOptIn {
                    Label("Opt-In Rule", systemImage: "star.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                
                if viewModel.isEnabled {
                    Label("Enabled", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                
                if rule.supportsAutocorrection {
                    Label("Auto-correctable", systemImage: "wand.and.stars")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
                
                if let minVersion = rule.minimumSwiftVersion {
                    Label("Swift \(minVersion)+", systemImage: "swift")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Show markdown documentation if available - directly below description
            if let markdownDoc = rule.markdownDocumentation, !markdownDoc.isEmpty {
                // Determine top padding: only add spacing if we showed the short description above
                let hasShortDescription = shouldShowShortDescription

                // Use the pre-built attributed string cached by rebuildAttributedString().
                // NSAttributedString HTML init must NOT be called here inside body - it
                // requires the main thread and SwiftUI layout passes can evaluate body
                // from non-main threads, causing the
                // "SOME_OTHER_THREAD_SWALLOWED_AT_LEAST_ONE_EXCEPTION" crash.
                if let attributedString = cachedAttributedString {
                    Text(attributedString)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.top, hasShortDescription ? 8 : 0)
                } else {
                    // Fallback to plain text (shown before cache is ready or on parse failure)
                    let processedContent = processContentForDisplay(content: markdownDoc)
                    Text(processedContent)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.top, hasShortDescription ? 8 : 0)
                }
            } else if rule.description.isEmpty || rule.description == "No description available" {
                // Show message if we have neither description nor markdown documentation
                Text("No description available")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            // Attribution
            let docURL = rule.documentation
                ?? URL(string: "https://realm.github.io/SwiftLint/\(rule.id).html")
            if let url = docURL {
                Link(destination: url) {
                    Label("Source: SwiftLint documentation", systemImage: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }
    
    var configurationView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 16) {
                // Toggle at the top with full width
                HStack {
                    Toggle("Enable this rule", isOn: Binding(
                        get: { viewModel.isEnabled },
                        set: { viewModel.updateEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                
                if viewModel.isEnabled {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Severity")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Picker("Severity", selection: Binding(
                            get: { viewModel.severity ?? .warning },
                            set: { viewModel.updateSeverity($0) }
                        )) {
                            ForEach(Severity.allCases) { severity in
                                Text(severity.displayName).tag(severity)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 300)
                    }

                    if let parameters = rule.parameters, !parameters.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Parameters")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            RuleParameterEditor(
                                parameters: parameters,
                                values: $viewModel.parameterValues
                            )
                        }
                    }
                }

                if viewModel.pendingChanges != nil {
                    Divider()
                    
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text("You have unsaved changes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Simulate button
                if dependencies.workspaceManager.currentWorkspace != nil {
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 8))
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
                        .foregroundStyle(.red)
                    
                    ForEach(Array(rule.triggeringExamples.enumerated()), id: \.offset) { _, example in
                        CodeBlock(code: example, isError: true)
                    }
                }
            }
            
            if !rule.nonTriggeringExamples.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Non-Triggering Examples", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                    
                    ForEach(Array(rule.nonTriggeringExamples.enumerated()), id: \.offset) { _, example in
                        CodeBlock(code: example, isError: false)
                    }
                }
            }
            
            if rule.triggeringExamples.isEmpty && rule.nonTriggeringExamples.isEmpty {
                Text("No examples available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                    if let attributedString = cachedAttributedString {
                        Text(attributedString)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        let processedContent = processContentForDisplay(content: markdown)
                        Text(processedContent)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical)
                .padding(.trailing)
                .padding(.leading)
            }
            .frame(maxHeight: 500)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 8))
        }
    }
    
    var whyThisMattersView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why This Matters")
                .font(.headline)
            
            if let rationale = extractRationale(from: rule.markdownDocumentation ?? "") {
                Text(rationale)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                Text("No rationale available")
                    .font(.body)
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(violationCount > 0 ? .orange : .green)
                    
                    Text(violationCount == 1 ? "violation" : "violations")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    
                    if violationCount > 0 {
                        Text("in current workspace")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(related.prefix(5), id: \.id) { relatedRule in
                        Button {
                            // Navigate to related rule - would need navigation handling
                        } label: {
                            HStack(alignment: .center, spacing: 8) {
                                Text(relatedRule.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(2)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if related.count > 5 {
                        Text("+ \(related.count - 5) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(links, id: \.self) { link in
                        Link(destination: link) {
                            HStack(alignment: .center, spacing: 8) {
                                Image(systemName: "link")
                                    .font(.caption)
                                    .accessibilityHidden(true)
                                Text(link.absoluteString)
                                    .font(.body)
                                    .foregroundStyle(.blue)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}
