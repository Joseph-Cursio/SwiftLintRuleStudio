import Foundation
import SwiftLintCLISeam

extension RuleRegistry {
    /// Enriches rules with detailed documentation fetched from SwiftLint
    public func updateRulesWithDetails(_ rules: [Rule]) async -> [Rule] {
        let rulesToFetchDetails = Array(rules.prefix(20))
        var updatedRules = rules

        await withTaskGroup(of: (Int, Rule).self) { group in
            for (index, rule) in rulesToFetchDetails.enumerated() {
                group.addTask {
                    await self.fetchDetailedRuleResult(rule: rule, index: index)
                }
            }

            for await (index, detailedRule) in group {
                updatedRules[index] = detailedRule
                self.updateRules(updatedRules)
            }
        }

        return updatedRules
    }

    private func fetchDetailedRuleResult(rule: Rule, index: Int) async -> (Int, Rule) {
        do {
            let detailedRule = try await fetchRuleDetailsWithTimeout(rule: rule)
            return (index, detailedRule)
        } catch {
            return (index, rule)
        }
    }

    private func fetchRuleDetailsWithTimeout(rule: Rule) async throws -> Rule {
        try await withThrowingTaskGroup(of: Rule.self) { timeoutGroup in
            timeoutGroup.addTask {
                try await self.fetchRuleDetails(
                    identifier: rule.id,
                    category: rule.category,
                    isOptIn: rule.isOptIn,
                    isAnalyzer: rule.isAnalyzer,
                    usesSourceKit: rule.usesSourceKit
                )
            }
            timeoutGroup.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw NSError(
                    domain: "RuleRegistry",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Rule detail fetch timed out for \(rule.id)"]
                )
            }

            guard let result = try await timeoutGroup.next() else {
                throw NSError(
                    domain: "RuleRegistry",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Rule detail fetch cancelled for \(rule.id)"]
                )
            }
            timeoutGroup.cancelAll()
            return result
        }
    }

    /// Fetches detailed documentation for a single rule by identifier
    public func fetchRuleDetails(
        identifier: String,
        category: RuleCategory,
        isOptIn: Bool,
        isAnalyzer: Bool = false,
        usesSourceKit: Bool = false
    ) async throws -> Rule {
        try await Self.fetchRuleDetailsHelper(
            identifier: identifier,
            category: category,
            isOptIn: isOptIn,
            swiftLintCLI: swiftLintCLI,
            isAnalyzer: isAnalyzer,
            usesSourceKit: usesSourceKit
        )
    }

    /// Helper to fetch rule details without requiring self (to avoid data race warnings)
    public static func fetchRuleDetailsHelper(
        identifier: String,
        category: RuleCategory,
        isOptIn: Bool,
        swiftLintCLI: SwiftLintCLIProtocol,
        isAnalyzer: Bool = false,
        usesSourceKit: Bool = false
    ) async throws -> Rule {
        var state = RuleDetailsState(
            identifier: identifier,
            isOptIn: isOptIn,
            isAnalyzer: isAnalyzer,
            usesSourceKit: usesSourceKit,
            name: identifier.replacingOccurrences(of: "_", with: " ").capitalized
        )
        await populateFromDocs(ruleId: identifier, swiftLintCLI: swiftLintCLI, state: &state)
        // Always pull from `swiftlint rules <id>` for parameter schema (markdown docs
        // don't expose it in a parseable form). Reuse the same output to fill in
        // examples when the docs path didn't supply any.
        try await populateFromRuleDetails(ruleId: identifier, swiftLintCLI: swiftLintCLI, state: &state)
        return state.asRule(category: category)
    }

    private struct RuleDetailsState {
        let identifier: String
        let isOptIn: Bool
        let isAnalyzer: Bool
        let usesSourceKit: Bool
        var name: String
        var description: String = "No description available"
        var triggeringExamples: [String] = []
        var nonTriggeringExamples: [String] = []
        var supportsAutocorrection: Bool = false
        var minimumSwiftVersion: String?
        var defaultSeverity: Severity?
        var markdownDoc: String?
        var parameters: [RuleParameter]?

        mutating func apply(_ doc: ParsedRuleDocumentation) {
            if !doc.name.isEmpty {
                name = doc.name
            }
            if !doc.description.isEmpty {
                description = doc.description
            }
            triggeringExamples = doc.triggeringExamples
            nonTriggeringExamples = doc.nonTriggeringExamples
            supportsAutocorrection = doc.supportsAutocorrection
            minimumSwiftVersion = doc.minimumSwiftVersion
            defaultSeverity = doc.defaultSeverity
        }

        func asRule(category: RuleCategory) -> Rule {
            Rule(
                id: identifier,
                name: name,
                description: description,
                category: category,
                isOptIn: isOptIn,
                isAnalyzer: isAnalyzer,
                usesSourceKit: usesSourceKit,
                severity: defaultSeverity,
                parameters: parameters,
                triggeringExamples: triggeringExamples,
                nonTriggeringExamples: nonTriggeringExamples,
                documentation: nil,
                isEnabled: !isOptIn,
                supportsAutocorrection: supportsAutocorrection,
                minimumSwiftVersion: minimumSwiftVersion,
                defaultSeverity: defaultSeverity,
                markdownDocumentation: markdownDoc
            )
        }
    }

    private static func populateFromDocs(
        ruleId: String,
        swiftLintCLI: SwiftLintCLIProtocol,
        state: inout RuleDetailsState
    ) async {
        guard let markdown = try? await swiftLintCLI.generateDocsForRule(ruleId: ruleId) else { return }
        state.markdownDoc = markdown
        guard !markdown.isEmpty else {
            return
        }
        let parsedDoc = RuleDocumentationParser.parse(markdown: markdown)
        state.apply(parsedDoc)
    }

    private static func populateFromRuleDetails(
        ruleId: String,
        swiftLintCLI: SwiftLintCLIProtocol,
        state: inout RuleDetailsState
    ) async throws {
        let detailData = try await swiftLintCLI.executeRuleDetailCommand(ruleId: ruleId)
        guard let detailText = String(data: detailData, encoding: .utf8) else {
            return
        }
        // Parameter schema only lives in this CLI output, not in the markdown docs,
        // so always parse it.
        state.parameters = RuleParameterParser.parseParameters(from: detailText, ruleId: ruleId)
        // Examples and header are only filled when the docs path didn't already
        // populate them — the docs are the more reliable source.
        if state.triggeringExamples.isEmpty && state.nonTriggeringExamples.isEmpty {
            let lines = detailText.components(separatedBy: .newlines)
            applyRuleHeader(lines: lines, state: &state)
            applyRuleExamples(lines: lines, state: &state)
        }
    }

    private static func applyRuleHeader(lines: [String], state: inout RuleDetailsState) {
        guard let firstLine = lines.first, firstLine.contains("(") else { return }
        let parts = firstLine.components(separatedBy: ":")
        guard parts.count >= 2 else { return }
        let namePart = parts[0].trimmingCharacters(in: .whitespaces)
        if let parenStart = namePart.range(of: "(") {
            state.name = String(namePart[..<parenStart.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        if state.description == "No description available" {
            state.description = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
        }
    }

    /// Which examples section of `swiftlint rules <id>` output a line belongs to.
    private enum ExampleSection {
        case triggering
        case nonTriggering
    }

    /// The examples in `swiftlint rules <id>` output, the fallback when the generated docs gave none.
    ///
    /// SwiftLint prints a blank line after each section header and numbers each example
    /// `Example #n`. Every flush used to end the section, an empty flush included, so the blank
    /// line after the header ended it before the first example and real output yielded no
    /// examples at all; a flush that did append one ended the section too, so at most one per
    /// section survived. A section now lasts until the next header. Blank lines and `Example #`
    /// still separate examples.
    private static func applyRuleExamples(lines: [String], state: inout RuleDetailsState) {
        var section: ExampleSection?
        var currentExample: [String] = []

        for line in lines {
            if line.contains("Non-Triggering Examples") || line.contains("Non Triggering Examples") {
                flushExample(&currentExample, into: section, state: &state)
                section = .nonTriggering
                continue
            }
            if line.contains("Triggering Examples") {
                flushExample(&currentExample, into: section, state: &state)
                section = .triggering
                continue
            }
            // The configuration header ends the examples. It starts its line; example code is
            // indented, so a `Configuration` type inside an example does not end anything.
            if line.hasPrefix("Configuration") {
                flushExample(&currentExample, into: section, state: &state)
                section = nil
                continue
            }
            guard section != nil else { continue }

            if line.contains("Example #") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushExample(&currentExample, into: section, state: &state)
                continue
            }

            let cleanLine = line.replacingOccurrences(of: "↓", with: "").trimmingCharacters(in: .whitespaces)
            if !cleanLine.isEmpty {
                currentExample.append(cleanLine)
            }
        }

        flushExample(&currentExample, into: section, state: &state)
    }

    private static func flushExample(
        _ currentExample: inout [String],
        into section: ExampleSection?,
        state: inout RuleDetailsState
    ) {
        let example = currentExample.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        currentExample = []
        guard !example.isEmpty, let section else { return }
        switch section {
        case .triggering:
            state.triggeringExamples.append(example)

        case .nonTriggering:
            state.nonTriggeringExamples.append(example)
        }
    }
}
