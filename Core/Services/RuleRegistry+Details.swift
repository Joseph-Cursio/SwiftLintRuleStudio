import Foundation

extension RuleRegistry {
    func updateRulesWithDetails(_ rules: [Rule]) async -> [Rule] {
        let rulesToFetchDetails = Array(rules.prefix(20))
        var updatedRules = rules

        await withTaskGroup(of: (Int, Rule).self) { group in
            for (index, rule) in rulesToFetchDetails.enumerated() {
                group.addTask { [weak self] in
                    guard let self = self else { return (index, rule) }
                    return await self.fetchDetailedRuleResult(rule: rule, index: index)
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
            print("⚠️ Failed to fetch details for rule \(rule.id): \(error.localizedDescription)")
            return (index, rule)
        }
    }
    
    private func fetchRuleDetailsWithTimeout(rule: Rule) async throws -> Rule {
        try await withThrowingTaskGroup(of: Rule.self) { timeoutGroup in
            timeoutGroup.addTask {
                try await self.fetchRuleDetails(
                    identifier: rule.id,
                    category: rule.category,
                    isOptIn: rule.isOptIn
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
    
    func fetchRuleDetails(identifier: String, category: RuleCategory, isOptIn: Bool) async throws -> Rule {
        return try await Self.fetchRuleDetailsHelper(
            identifier: identifier,
            category: category,
            isOptIn: isOptIn,
            swiftLintCLI: swiftLintCLI
        )
    }
    
    /// Helper to fetch rule details without requiring self (to avoid data race warnings)
    static func fetchRuleDetailsHelper(
        identifier: String,
        category: RuleCategory,
        isOptIn: Bool,
        swiftLintCLI: SwiftLintCLIProtocol
    ) async throws -> Rule {
        var state = RuleDetailsState(identifier: identifier, isOptIn: isOptIn)
        await populateFromDocs(ruleId: identifier, swiftLintCLI: swiftLintCLI, state: &state)
        if state.triggeringExamples.isEmpty && state.nonTriggeringExamples.isEmpty {
            try await populateFromRuleDetails(ruleId: identifier, swiftLintCLI: swiftLintCLI, state: &state)
        }
        return state.asRule(category: category)
    }

    private struct RuleDetailsState {
        let identifier: String
        let isOptIn: Bool
        var name: String
        var description: String
        var triggeringExamples: [String]
        var nonTriggeringExamples: [String]
        var supportsAutocorrection: Bool
        var minimumSwiftVersion: String?
        var defaultSeverity: Severity?
        var markdownDoc: String?

        init(identifier: String, isOptIn: Bool) {
            self.identifier = identifier
            self.isOptIn = isOptIn
            name = identifier.replacingOccurrences(of: "_", with: " ").capitalized
            description = "No description available"
            triggeringExamples = []
            nonTriggeringExamples = []
            supportsAutocorrection = false
            minimumSwiftVersion = nil
            defaultSeverity = nil
            markdownDoc = nil
        }

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
                severity: defaultSeverity,
                parameters: nil,
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
        do {
            let markdown = try await swiftLintCLI.generateDocsForRule(ruleId: ruleId)
            state.markdownDoc = markdown
            guard !markdown.isEmpty else {
                print("⚠️ generate-docs returned empty markdown for \(ruleId)")
                return
            }
            let parsedDoc = RuleDocumentationParser.parse(markdown: markdown)
            state.apply(parsedDoc)
        } catch {
            print("⚠️ generate-docs failed for \(ruleId), falling back to rules command: \(error.localizedDescription)")
        }
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
        let lines = detailText.components(separatedBy: .newlines)
        applyRuleHeader(lines: lines, state: &state)
        applyRuleExamples(lines: lines, state: &state)
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

    private static func applyRuleExamples(lines: [String], state: inout RuleDetailsState) {
        var inTriggeringExamples = false
        var inNonTriggeringExamples = false
        var currentExample: [String] = []

        for line in lines {
            if line.contains("Non-Triggering Examples") || line.contains("Non Triggering Examples") {
                inNonTriggeringExamples = true
                inTriggeringExamples = false
                continue
            }
            if line.contains("Triggering Examples") {
                inTriggeringExamples = true
                inNonTriggeringExamples = false
                continue
            }
            if line.contains("Configuration") || line.isEmpty {
                flushExample(
                    inTriggeringExamples: &inTriggeringExamples,
                    inNonTriggeringExamples: &inNonTriggeringExamples,
                    currentExample: &currentExample,
                    state: &state
                )
                continue
            }
            guard inTriggeringExamples || inNonTriggeringExamples else { continue }

            if line.contains("Example #") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushExample(
                    inTriggeringExamples: &inTriggeringExamples,
                    inNonTriggeringExamples: &inNonTriggeringExamples,
                    currentExample: &currentExample,
                    state: &state
                )
                continue
            }

            let cleanLine = line.replacingOccurrences(of: "↓", with: "").trimmingCharacters(in: .whitespaces)
            if !cleanLine.isEmpty {
                currentExample.append(cleanLine)
            }
        }

        flushExample(
            inTriggeringExamples: &inTriggeringExamples,
            inNonTriggeringExamples: &inNonTriggeringExamples,
            currentExample: &currentExample,
            state: &state
        )
    }

    private static func flushExample(
        inTriggeringExamples: inout Bool,
        inNonTriggeringExamples: inout Bool,
        currentExample: inout [String],
        state: inout RuleDetailsState
    ) {
        guard !currentExample.isEmpty else {
            inTriggeringExamples = false
            inNonTriggeringExamples = false
            return
        }
        let example = currentExample.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if inTriggeringExamples && !example.isEmpty {
            state.triggeringExamples.append(example)
        } else if inNonTriggeringExamples && !example.isEmpty {
            state.nonTriggeringExamples.append(example)
        }
        currentExample = []
        inTriggeringExamples = false
        inNonTriggeringExamples = false
    }
}
