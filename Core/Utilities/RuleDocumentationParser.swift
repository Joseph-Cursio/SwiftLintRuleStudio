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
        let lines = markdown.components(separatedBy: .newlines)
        let (name, foundTitle) = parseTitle(from: lines)
        let description = extractDescription(from: lines, foundTitle: foundTitle)
        let metadata = extractMetadata(from: lines)
        let examples = extractExamples(from: lines)
        
        // Limit description length for list view (first 250 characters or first sentence)
        var trimmedDescription = description
        if !trimmedDescription.isEmpty && trimmedDescription.count > 250 {
            // Try to find a sentence boundary near 250 characters
            let truncated = String(trimmedDescription.prefix(250))
            if let lastPeriod = truncated.lastIndex(of: ".") {
                trimmedDescription = String(truncated[..<truncated.index(after: lastPeriod)])
                    .trimmingCharacters(in: .whitespaces)
            } else {
                // No period found, just truncate and add ellipsis
                trimmedDescription = truncated.trimmingCharacters(in: .whitespaces) + "..."
            }
        }
        
        return ParsedRuleDocumentation(
            name: name,
            description: trimmedDescription,
            supportsAutocorrection: metadata.supportsAutocorrection,
            minimumSwiftVersion: metadata.minimumSwiftVersion,
            defaultSeverity: metadata.defaultSeverity,
            triggeringExamples: examples.triggering,
            nonTriggeringExamples: examples.nonTriggering,
            fullMarkdown: markdown
        )
    }
    
    private enum SectionType {
        case triggering
        case nonTriggering
    }

    private struct Metadata {
        let supportsAutocorrection: Bool
        let minimumSwiftVersion: String?
        let defaultSeverity: Severity?
    }

    private struct Examples {
        let triggering: [String]
        let nonTriggering: [String]
    }

    private static func parseTitle(from lines: [String]) -> (String, Bool) {
        guard let firstLine = lines.first, firstLine.hasPrefix("#") else {
            return ("", false)
        }
        let name = String(firstLine.dropFirst()).trimmingCharacters(in: .whitespaces)
        return (name, true)
    }

    private static func extractDescription(from lines: [String], foundTitle: Bool) -> String {
        var descriptionLines: [String] = []
        let startIndex = foundTitle ? 1 : 0
        for line in lines.dropFirst(startIndex) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("* **") || trimmed.hasPrefix("##") || trimmed.hasPrefix("```") {
                break
            }
            if trimmed.isEmpty {
                if !descriptionLines.isEmpty {
                    break
                }
                continue
            }
            descriptionLines.append(trimmed)
        }
        return descriptionLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractMetadata(from lines: [String]) -> Metadata {
        var supportsAutocorrection = false
        var minimumSwiftVersion: String?
        var defaultSeverity: Severity?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("* **") {
                let content = trimmed.dropFirst(4)
                if let colonRange = content.range(of: ":**") {
                    let key = String(content[..<colonRange.lowerBound]).lowercased()
                    var value = String(content[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if value.hasPrefix("`") && value.hasSuffix("`") {
                        value = String(value.dropFirst().dropLast())
                    }
                    switch key {
                    case "supports autocorrection:":
                        supportsAutocorrection = value.lowercased() == "yes"
                    case "minimum swift compiler version:":
                        minimumSwiftVersion = value
                    default:
                        break
                    }
                }
            }

            if trimmed.contains("severity") && index < lines.count - 1 {
                if let severity = parseDefaultSeverity(from: lines, startIndex: index + 1) {
                    defaultSeverity = severity
                }
            }
        }

        return Metadata(
            supportsAutocorrection: supportsAutocorrection,
            minimumSwiftVersion: minimumSwiftVersion,
            defaultSeverity: defaultSeverity
        )
    }

    private static func parseDefaultSeverity(from lines: [String], startIndex: Int) -> Severity? {
        let endIndex = min(startIndex + 10, lines.count)
        for lookaheadIndex in startIndex..<endIndex {
            let nextLine = lines[lookaheadIndex].trimmingCharacters(in: .whitespaces)
            if nextLine.hasPrefix("<td>") && nextLine.contains("</td>") {
                let severityValue = nextLine
                    .replacingOccurrences(of: "<td>", with: "")
                    .replacingOccurrences(of: "</td>", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                if severityValue == "warning" || severityValue == "error" {
                    return Severity(rawValue: severityValue)
                }
                return nil
            }
        }
        return nil
    }

    private static func extractExamples(from lines: [String]) -> Examples {
        var state = ExampleState()
        for line in lines {
            state.processLine(line)
        }
        state.flushExample()
        return Examples(triggering: state.triggeringExamples, nonTriggering: state.nonTriggeringExamples)
    }

    private struct ExampleState {
        var triggeringExamples: [String] = []
        var nonTriggeringExamples: [String] = []
        private var currentSection: SectionType?
        private var currentExample: [String] = []
        private var inCodeBlock = false

        mutating func processLine(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if handleCodeFence(trimmed, line: line) {
                return
            }
            if inCodeBlock {
                currentExample.append(line)
                return
            }
            if handleSectionHeader(trimmed) {
                return
            }
        }

        mutating func flushExample() {
            let example = currentExample.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !example.isEmpty else {
                currentExample = []
                return
            }
            switch currentSection {
            case .triggering:
                triggeringExamples.append(example)
            case .nonTriggering:
                nonTriggeringExamples.append(example)
            default:
                break
            }
            currentExample = []
        }

        private mutating func handleCodeFence(_ trimmed: String, line: String) -> Bool {
            guard trimmed.hasPrefix("```") else { return false }
            if inCodeBlock {
                flushExample()
                inCodeBlock = false
            } else {
                inCodeBlock = true
                _ = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }
            return true
        }

        private mutating func handleSectionHeader(_ trimmed: String) -> Bool {
            guard trimmed.hasPrefix("##") else { return false }
            let sectionName = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces).lowercased()
            if sectionName.contains("triggering") {
                currentSection = .triggering
            } else if sectionName.contains("non triggering") || sectionName.contains("non-triggering") {
                currentSection = .nonTriggering
            } else {
                currentSection = nil
            }
            return true
        }
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

