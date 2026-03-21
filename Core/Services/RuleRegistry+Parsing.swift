import Foundation

extension RuleRegistry {
    private static let initialDetailBatchSize = 20

    func fetchRulesFromSwiftLint() async throws -> [Rule] {
        let output = try await swiftLintCLI.executeRulesCommand()
        return try await parseRules(from: output)
    }

    private func parseRules(from data: Data) async throws -> [Rule] {
        let text = try decodeRuleText(from: data)

        let rules = parseRulesTable(from: text)

        guard !rules.isEmpty else {
            let message = "No rules found in SwiftLint output. " +
                "Make sure SwiftLint is installed and accessible."
            throw NSError(
                domain: "RuleRegistry",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        let updatedRules = await updateRulesWithDetails(rules)

        let batchSize = Self.initialDetailBatchSize
        let remainingRules = Array(rules.suffix(from: min(batchSize, rules.count)))
        if !remainingRules.isEmpty {
            startBackgroundLoading(for: remainingRules, startingIndex: min(batchSize, rules.count))
        }

        return updatedRules
    }

    private func decodeRuleText(from data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "RuleRegistry",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode SwiftLint output"]
            )
        }
        return text
    }

    private func parseRulesTable(from text: String) -> [Rule] {
        text.components(separatedBy: .newlines).compactMap(parseRuleLine(from:))
    }

    private func parseRuleLine(from line: String) -> Rule? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard shouldParseRuleLine(trimmed) else { return nil }

        let columns = trimmed.split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard columns.count >= 5 else {
            return nil
        }

        let identifier = columns[0]
        guard !identifier.isEmpty && !identifier.contains("─") else { return nil }

        let optInStr = columns.count > 1 ? columns[1].lowercased() : "no"
        let isOptIn = optInStr == "yes"
        let kindStr = columns.count > 4 ? columns[4].lowercased() : "style"
        let category = mapCategory(kindStr)

        return Rule(
            id: identifier,
            name: identifier.replacingOccurrences(of: "_", with: " ").capitalized,
            description: "Loading...",
            category: category,
            isOptIn: isOptIn,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: !isOptIn,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: nil
        )
    }

    private func shouldParseRuleLine(_ trimmed: String) -> Bool {
        if trimmed.isEmpty || trimmed.hasPrefix("+") || !trimmed.hasPrefix("|") {
            return false
        }
        return !trimmed.lowercased().hasPrefix("| identifier ")
    }

    private func mapCategory(_ kind: String) -> RuleCategory {
        switch kind {
        case "style":
            return .style
        case "lint":
            return .lint
        case "metrics":
            return .metrics
        case "performance":
            return .performance
        case "idiomatic":
            return .idiomatic
        default:
            return .style
        }
    }
}
