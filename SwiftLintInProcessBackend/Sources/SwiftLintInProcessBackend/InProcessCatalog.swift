import Foundation
import SwiftLintFramework
// No `import SwiftLintRuleStudioCore` here: this file uses only SwiftLintFramework
// types, and Core also declares `Rule`/`RuleRegistry`, which would collide.

// Produces output in the exact shapes the app's parsers expect from the SwiftLint
// CLI, so the in-process backend is a drop-in for the subprocess one:
//   • JSON matching `swiftlint lint --reporter json` (WorkspaceAnalyzer decodes it)
//   • the `|`-delimited `swiftlint rules` table (RuleRegistry+Parsing)
//   • the `Name (id): description` rule-detail header (RuleRegistry+Details)
extension SwiftLintInProcessActor {

    // MARK: - Lint JSON (mirrors SwiftLintFramework's JSONReporter, which is internal)

    static func jsonReport(for violations: [StyleViolation]) -> String {
        let objects: [[String: Any]] = violations.map { violation in
            [
                "file": violation.location.file?.path ?? NSNull(),
                "line": violation.location.line ?? NSNull(),
                "character": violation.location.character ?? NSNull(),
                "severity": violation.severity.rawValue.capitalized,
                "type": violation.ruleName,
                "rule_id": violation.ruleIdentifier,
                "reason": violation.reason
            ]
        }
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: objects,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            ),
            let string = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return string
    }

    // MARK: - Rules catalog (mirrors `swiftlint rules`)

    static func sortedBuiltInRules() -> [any Rule.Type] {
        builtInRules.sorted { $0.description.identifier < $1.description.identifier }
    }

    static func ruleDescription(forID id: String) -> RuleDescription? {
        builtInRules
            .first { $0.description.allIdentifiers.contains(id) }?
            .description
    }

    static func rulesTable() -> String {
        let border =
            "+------------+--------+-------------+-------------------------+------+----------+----------------+"
        let header =
            "| identifier | opt-in | correctable | enabled in your config | kind | analyzer | uses sourcekit |"
        var lines = [border, header, border]
        for ruleType in sortedBuiltInRules() {
            let description = ruleType.description
            let optIn = ruleType is any OptInRule.Type ? "yes" : "no"
            let correctable = ruleType is any CorrectableRule.Type ? "yes" : "no"
            let analyzer = ruleType is any AnalyzerRule.Type ? "yes" : "no"
            let usesSourceKit = ruleType is any SourceKitFreeRule.Type ? "no" : "yes"
            let enabled = optIn == "yes" ? "no" : "yes"
            lines.append(
                "| \(description.identifier) | \(optIn) | \(correctable) | \(enabled) "
                + "| \(description.kind.rawValue) | \(analyzer) | \(usesSourceKit) |"
            )
        }
        lines.append(border)
        return lines.joined(separator: "\n")
    }

    // MARK: - Rule detail (mirrors `swiftlint rules <id>`)

    static func ruleDetailText(for description: RuleDescription) -> String {
        // First line = "Name (identifier): description" — the header parser keys
        // off the "(" and the ":".
        var lines = [description.consoleDescription, ""]
        if !description.nonTriggeringExamples.isEmpty {
            lines.append("Non Triggering Examples:")
            lines.append(contentsOf: description.nonTriggeringExamples.map(\.code))
            lines.append("")
        }
        if !description.triggeringExamples.isEmpty {
            lines.append("Triggering Examples:")
            lines.append(contentsOf: description.triggeringExamples.map(\.code))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Markdown docs (parsed by RuleDocumentationParser)

    static func markdownDoc(for description: RuleDescription) -> String {
        var markdown = "# \(description.name)\n\n\(description.description)\n\n"
        if let rationale = description.rationale, !rationale.isEmpty {
            markdown += "\(rationale)\n\n"
        }
        markdown += "* **Identifier:** \(description.identifier)\n"
        markdown += "* **Kind:** \(description.kind.rawValue)\n\n"
        if !description.nonTriggeringExamples.isEmpty {
            markdown += "## Non Triggering Examples\n\n"
            markdown += description.nonTriggeringExamples
                .map { "```swift\n\($0.code)\n```" }
                .joined(separator: "\n\n")
            markdown += "\n\n"
        }
        if !description.triggeringExamples.isEmpty {
            markdown += "## Triggering Examples\n\n"
            markdown += description.triggeringExamples
                .map { "```swift\n\($0.code)\n```" }
                .joined(separator: "\n\n")
            markdown += "\n"
        }
        return markdown
    }
}
