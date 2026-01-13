//
//  RuleDocumentationParser.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

/// Parser for SwiftLint rule documentation markdown files
struct RuleDocumentationParser {
    static func parse(markdown: String) -> ParsedRuleDocumentation {
        var name = ""
        var description = ""
        var supportsAutocorrection = false
        var minimumSwiftVersion: String?
        var defaultSeverity: Severity?
        var triggeringExamples: [String] = []
        var nonTriggeringExamples: [String] = []
        
        let lines = markdown.components(separatedBy: .newlines)
        var currentSection: SectionType?
        var currentExample: [String] = []
        var inCodeBlock = false
        var descriptionLines: [String] = []
        var foundTitle = false
        
        // Parse title (first line is usually the rule name)
        if let firstLine = lines.first, firstLine.hasPrefix("#") {
            name = String(firstLine.dropFirst()).trimmingCharacters(in: .whitespaces)
            foundTitle = true
        }
        
        // Parse metadata and examples
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip the title line
            if index == 0 && foundTitle {
                continue
            }
            
            // Collect description lines - everything after title until we hit metadata or section headers
            // Stop collecting when we encounter:
            // - Metadata lines (starting with "* **")
            // - Section headers (starting with "##")
            // - Code blocks (starting with "```")
            // - Empty lines that indicate end of description paragraph
            if description.isEmpty {
                if trimmed.hasPrefix("* **") || trimmed.hasPrefix("##") || trimmed.hasPrefix("```") {
                    // We've hit metadata or a section, stop collecting description
                    if !descriptionLines.isEmpty {
                        description = descriptionLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                        descriptionLines = [] // Clear to prevent re-collecting
                    }
                } else if !trimmed.isEmpty {
                    // Collect non-empty lines for description
                    descriptionLines.append(trimmed)
                } else if !descriptionLines.isEmpty {
                    // Empty line after description - we've reached the end of the first paragraph
                    description = descriptionLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    descriptionLines = [] // Clear to prevent re-collecting
                }
            }
            
            // Detect code blocks
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    // End of code block - save the example
                    if !currentExample.isEmpty {
                        let example = currentExample.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !example.isEmpty {
                            switch currentSection {
                            case .triggering:
                                triggeringExamples.append(example)
                            case .nonTriggering:
                                nonTriggeringExamples.append(example)
                            default:
                                break
                            }
                        }
                        currentExample = []
                    }
                    inCodeBlock = false
                } else {
                    // Start of code block
                    inCodeBlock = true
                    // Language identifier is extracted but not currently used
                    _ = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            
            // If we're in a code block, collect lines
            if inCodeBlock {
                currentExample.append(line)
                continue
            }
            
            // Parse metadata
            if trimmed.hasPrefix("* **") {
                // Parse key-value pairs like "* **Identifier:** `force_cast`"
                let content = trimmed.dropFirst(4) // Remove "* **"
                if let colonRange = content.range(of: ":**") {
                    let key = String(content[..<colonRange.lowerBound]).lowercased()
                    var value = String(content[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    
                    // Remove backticks if present
                    if value.hasPrefix("`") && value.hasSuffix("`") {
                        value = String(value.dropFirst().dropLast())
                    }
                    
                    switch key {
                    case "supports autocorrection:":
                        supportsAutocorrection = value.lowercased() == "yes"
                    case "minimum swift compiler version:":
                        minimumSwiftVersion = value
                    case "default configuration:":
                        // This is a table, we'll parse it below
                        break
                    default:
                        break
                    }
                }
            }
            
            // Parse default configuration table for severity
            if trimmed.contains("severity") && index < lines.count - 1 {
                // Look for the severity value in the next few lines
                for i in (index + 1)..<min(index + 10, lines.count) {
                    let nextLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if nextLine.hasPrefix("<td>") && nextLine.contains("</td>") {
                        let severityValue = nextLine
                            .replacingOccurrences(of: "<td>", with: "")
                            .replacingOccurrences(of: "</td>", with: "")
                            .trimmingCharacters(in: .whitespaces)
                            .lowercased()
                        if severityValue == "warning" || severityValue == "error" {
                            defaultSeverity = Severity(rawValue: severityValue)
                        }
                        break
                    }
                }
            }
            
            // Detect section headers
            if trimmed.hasPrefix("##") {
                let sectionName = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces).lowercased()
                if sectionName.contains("triggering") {
                    currentSection = .triggering
                } else if sectionName.contains("non triggering") || sectionName.contains("non-triggering") {
                    currentSection = .nonTriggering
                } else {
                    currentSection = nil
                }
                continue
            }
        }
        
        // If we still have collected description lines, use them
        if description.isEmpty && !descriptionLines.isEmpty {
            description = descriptionLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Limit description length for list view (first 250 characters or first sentence)
        if !description.isEmpty && description.count > 250 {
            // Try to find a sentence boundary near 250 characters
            let truncated = String(description.prefix(250))
            if let lastPeriod = truncated.lastIndex(of: ".") {
                description = String(description[..<description.index(after: lastPeriod)]).trimmingCharacters(in: .whitespaces)
            } else {
                // No period found, just truncate and add ellipsis
                description = truncated.trimmingCharacters(in: .whitespaces) + "..."
            }
        }
        
        return ParsedRuleDocumentation(
            name: name,
            description: description,
            supportsAutocorrection: supportsAutocorrection,
            minimumSwiftVersion: minimumSwiftVersion,
            defaultSeverity: defaultSeverity,
            triggeringExamples: triggeringExamples,
            nonTriggeringExamples: nonTriggeringExamples,
            fullMarkdown: markdown
        )
    }
    
    private enum SectionType {
        case triggering
        case nonTriggering
    }
}

struct ParsedRuleDocumentation {
    let name: String
    let description: String
    let supportsAutocorrection: Bool
    let minimumSwiftVersion: String?
    let defaultSeverity: Severity?
    let triggeringExamples: [String]
    let nonTriggeringExamples: [String]
    let fullMarkdown: String
}

