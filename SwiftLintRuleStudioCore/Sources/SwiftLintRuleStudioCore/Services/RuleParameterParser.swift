//
//  RuleParameterParser.swift
//  SwiftLintRuleStudio
//
//  Parses the "Configuration (YAML):" block from `swiftlint rules <id>`
//  output into a [RuleParameter] schema usable by the rule-detail UI.
//

import Foundation
import Yams

public enum RuleParameterParser {

    /// Parses `swiftlint rules <ruleId>` output and returns the rule's
    /// configurable parameters, or nil if none could be extracted.
    /// `ruleId` is the SwiftLint rule identifier (e.g. "cyclomatic_complexity").
    public static func parseParameters(
        from cliOutput: String,
        ruleId: String
    ) -> [RuleParameter]? {
        guard let yamlBlock = extractYAMLBlock(from: cliOutput) else { return nil }
        // SwiftLint emits some "Configuration (YAML):" blocks that are documentation
        // placeholders rather than real YAML (e.g. `required_enum_case` shows
        // `{Protocol Name}: {Case Name 1}: {warning|error}`). Yams fatal-errors
        // on those, so reject them before they reach the parser.
        guard !looksLikePlaceholderYAML(yamlBlock) else { return nil }
        guard let root = try? Yams.load(yaml: yamlBlock) as? [String: Any] else { return nil }
        // SwiftLint wraps the parameters under the rule id, e.g.
        //   cyclomatic_complexity:
        //     warning: 10
        // Tolerate the wrapper missing (top-level scalars) by treating root as the body.
        let body = (root[ruleId] as? [String: Any]) ?? root
        let params = body.compactMap { (key, value) -> RuleParameter? in
            buildParameter(name: key, value: value)
        }
        // Preserve insertion order from the YAML source for stable UI display.
        let orderedKeys = orderedTopLevelKeys(in: yamlBlock, under: ruleId)
        let byName = Dictionary(uniqueKeysWithValues: params.map { ($0.name, $0) })
        let ordered = orderedKeys.compactMap { byName[$0] }
        return ordered.isEmpty ? nil : ordered
    }

    /// Returns true when the YAML block looks like documentation rather than a
    /// real config (keys shaped like `{Protocol Name}:` or `{Case Name}: {warning|error}`).
    static func looksLikePlaceholderYAML(_ yamlBlock: String) -> Bool {
        for line in yamlBlock.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("{") {
                // A line beginning with `{` is either a placeholder mapping key
                // or a flow-style mapping. Neither shows up in real SwiftLint
                // rule configs — they all start with a plain identifier.
                return true
            }
        }
        return false
    }

    /// Extracts the indented YAML block following the "Configuration (YAML):" header,
    /// stopping at the next blank-line-separated section (e.g. "Triggering Examples").
    /// Returns the de-indented YAML, or nil if the header is absent.
    static func extractYAMLBlock(from cliOutput: String) -> String? {
        let lines = cliOutput.components(separatedBy: "\n")
        guard let headerIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "Configuration (YAML):"
        }) else { return nil }
        var blockLines: [String] = []
        var sawContent = false
        for line in lines[(headerIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Stop at the next section header (a non-indented line with text)
            // once we have started capturing content.
            if sawContent && !line.hasPrefix(" ") && !line.hasPrefix("\t") && !trimmed.isEmpty {
                break
            }
            if !trimmed.isEmpty {
                sawContent = true
                blockLines.append(line)
            } else if sawContent {
                // A blank line after content also terminates the block.
                break
            }
        }
        guard !blockLines.isEmpty else { return nil }
        return deindent(blockLines).joined(separator: "\n")
    }

    /// Strips the smallest common leading-whitespace prefix from every line.
    private static func deindent(_ lines: [String]) -> [String] {
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let leadingCounts = nonEmpty.map { line -> Int in
            line.prefix(while: { $0 == " " }).count
        }
        let minIndent = leadingCounts.min() ?? 0
        guard minIndent > 0 else { return lines }
        return lines.map { line in
            guard line.count >= minIndent else { return line }
            return String(line.dropFirst(minIndent))
        }
    }

    /// Returns the top-level keys *inside* the rule-id wrapper, in source order.
    /// If the wrapper is absent, returns the top-level keys of the block itself.
    private static func orderedTopLevelKeys(in yamlBlock: String, under ruleId: String) -> [String] {
        let lines = yamlBlock.components(separatedBy: "\n")
        guard let wrapperIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(ruleId):")
        }) else {
            // No wrapper — treat any line that looks like "key:" at the top
            // level as a top-level parameter.
            return lines.compactMap { keyName(from: $0, expectedIndent: 0) }
        }
        // The wrapper's children are indented by some N > 0; capture keys at
        // exactly that indent until we leave that block.
        let after = Array(lines.suffix(from: wrapperIndex + 1))
        let childIndent: Int? = after
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map { $0.prefix(while: { $0 == " " }).count }
        guard let indent = childIndent, indent > 0 else { return [] }
        return after.compactMap { keyName(from: $0, expectedIndent: indent) }
    }

    /// Returns the key portion of a "key: value" YAML line if (and only if)
    /// the line is indented by exactly `expectedIndent` spaces. This skips
    /// list items ("- foo") and deeper-indented nested keys.
    private static func keyName(from line: String, expectedIndent: Int) -> String? {
        let leading = line.prefix(while: { $0 == " " }).count
        guard leading == expectedIndent else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.firstIndex(of: ":"), !trimmed.hasPrefix("-") else { return nil }
        let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : key
    }

    /// Builds a single `RuleParameter` from a parsed YAML key-value pair,
    /// or returns nil if the value shape isn't representable by the current
    /// parameter model (nested mappings, severity-only keys, etc.).
    private static func buildParameter(name: String, value: Any) -> RuleParameter? {
        // The Severity picker handles top-level `severity:` directly; skip
        // it here so it doesn't appear twice in the rule detail UI.
        if name == "severity" { return nil }
        // Nested mappings (e.g. identifier_name.min_length.warning) aren't
        // representable by the current flat RuleParameter model.
        if value is [String: Any] || value is NSDictionary { return nil }

        // Bool must be checked before Int: NSNumber bridging means `true`/`false`
        // also satisfy `as? Int`, so an Int-first check would mis-classify booleans
        // as integer 0/1. isYAMLBool reads the underlying CFBoolean type id.
        if isYAMLBool(value), let boolValue = value as? Bool {
            return RuleParameter(name: name, type: .boolean, defaultValue: AnyCodable(boolValue))
        }
        if let intValue = value as? Int {
            return RuleParameter(name: name, type: .integer, defaultValue: AnyCodable(intValue))
        }
        if let stringValue = value as? String {
            return RuleParameter(name: name, type: .string, defaultValue: AnyCodable(stringValue))
        }
        if let arrayValue = value as? [Any] {
            return RuleParameter(name: name, type: .array, defaultValue: AnyCodable(arrayValue))
        }
        return nil
    }

    /// Yams decodes YAML booleans as `Bool`, but `Bool` also satisfies `as? Int`
    /// in Swift. Inspect the ObjC bridge to know whether the underlying token
    /// was actually a boolean.
    private static func isYAMLBool(_ value: Any) -> Bool {
        let typeName = String(describing: type(of: value))
        if typeName == "Bool" || typeName == "NSNumber" {
            let number = value as? NSNumber
            return CFGetTypeID(number) == CFBooleanGetTypeID()
        }
        return false
    }
}
