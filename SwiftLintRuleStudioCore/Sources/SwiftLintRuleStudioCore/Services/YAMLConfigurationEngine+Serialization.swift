import Foundation
import Yams

extension YAMLConfigurationEngine {
    /// Serialize a YAML configuration to a string, preserving the top-level
    /// key order from the loaded file when possible so that round-tripping a
    /// user's `.swiftlint.yml` doesn't reorganize their layout.
    public func serialize(_ config: YAMLConfig) throws -> String {
        do {
            let pairs = try orderedTopLevelPairs(for: config)
            let mapping = Node.Mapping(pairs)
            let node = Node.mapping(mapping)
            let yamlString = try Yams.serialize(node: node)
            let indented = Self.indentBlockSequences(in: yamlString)
            return reinsertComments(into: indented, config: config)
        } catch {
            throw YAMLConfigError.serializationError(error.localizedDescription)
        }
    }

    /// Re-indent block-sequence items two spaces under their parent key.
    ///
    /// Yams (via libyaml) emits block sequences "indentless" — each `- item`
    /// sits at the same column as its parent mapping key. SwiftLint configs
    /// are conventionally hand-written with sequence items indented two spaces
    /// under the key, so a naive round-trip would flip every list and produce
    /// noisy diffs. Adding two spaces to each sequence-item line restores the
    /// conventional style while keeping each item exactly two columns deeper
    /// than its key (nesting included). Comments are reinserted afterwards, so
    /// this pass only ever sees Yams output and never touches `#` lines.
    static func indentBlockSequences(in yaml: String) -> String {
        yaml
            .components(separatedBy: .newlines)
            .map { line -> String in
                let trimmed = line.drop { $0 == " " }
                guard trimmed == "-" || trimmed.hasPrefix("- ") else { return line }
                return "  " + line
            }
            .joined(separator: "\n")
    }

    /// Build the ordered list of (key, value) pairs for the top-level mapping.
    ///
    /// Order priority:
    /// 1. Keys in `config.keyOrder` (preserves the user's original file layout)
    /// 2. Reserved SwiftLint keys not yet emitted, in `defaultTopLevelKeyOrder`
    /// 3. Per-rule configuration keys, alphabetically (stable output)
    private func orderedTopLevelPairs(for config: YAMLConfig) throws -> [(Node, Node)] {
        let keyValues = try collectTopLevelKeyValues(from: config)
        var pairs: [(Node, Node)] = []
        var seen: Set<String> = []

        for key in config.keyOrder {
            guard !seen.contains(key), let value = keyValues[key] else { continue }
            pairs.append((Node(key), value))
            seen.insert(key)
        }

        for key in Self.defaultTopLevelKeyOrder where !seen.contains(key) {
            if let value = keyValues[key] {
                pairs.append((Node(key), value))
                seen.insert(key)
            }
        }

        let remaining = keyValues.keys.filter { !seen.contains($0) }.sorted()
        for key in remaining {
            if let value = keyValues[key] {
                pairs.append((Node(key), value))
            }
        }

        return pairs
    }

    /// Collect every top-level YAML key the config wants to emit, mapped to
    /// its already-serialized Node value.
    private func collectTopLevelKeyValues(from config: YAMLConfig) throws -> [String: Node] {
        var result: [String: Node] = [:]

        if let included = config.included { result["included"] = try Node(included) }
        if let excluded = config.excluded { result["excluded"] = try Node(excluded) }
        if let reporter = config.reporter { result["reporter"] = Node(reporter) }
        if let disabledRules = config.disabledRules { result["disabled_rules"] = try Node(disabledRules) }
        if let optInRules = config.optInRules { result["opt_in_rules"] = try Node(optInRules) }
        if let analyzerRules = config.analyzerRules { result["analyzer_rules"] = try Node(analyzerRules) }
        if let onlyRules = config.onlyRules { result["only_rules"] = try Node(onlyRules) }

        for (ruleId, ruleConfig) in config.rules {
            guard let value = topLevelRuleValue(for: ruleConfig) else { continue }
            result[ruleId] = try Node(value)
        }

        return result
    }

    /// Conventional emission order for reserved top-level SwiftLint keys when
    /// the loaded file didn't already provide an ordering for them.
    private static let defaultTopLevelKeyOrder: [String] = [
        "included",
        "excluded",
        "disabled_rules",
        "opt_in_rules",
        "analyzer_rules",
        "only_rules",
        "warning_threshold",
        "strict",
        "lenient",
        "reporter"
    ]

    private func topLevelRuleValue(for ruleConfig: RuleConfiguration) -> [String: Any]? {
        let hasSeverity = ruleConfig.severity != nil
        let hasParameters = !(ruleConfig.parameters?.isEmpty ?? true)
        guard hasSeverity || hasParameters else { return nil }

        var ruleDict: [String: Any] = [:]
        if let severity = ruleConfig.severity {
            ruleDict["severity"] = severity.rawValue
        }
        if let parameters = ruleConfig.parameters {
            for (key, value) in parameters {
                ruleDict[key] = value.value
            }
        }
        return ruleDict
    }
}
