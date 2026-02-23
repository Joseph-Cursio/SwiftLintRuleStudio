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
}
