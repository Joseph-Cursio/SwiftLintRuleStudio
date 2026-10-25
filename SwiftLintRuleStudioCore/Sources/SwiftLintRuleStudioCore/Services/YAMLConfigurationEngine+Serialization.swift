import Foundation
import Yams

extension YAMLConfigurationEngine {
    /// Serialize a YAML configuration to a string, preserving the top-level
    /// key order from the loaded file when possible so that round-tripping a
    /// user's `.swiftlint.yml` doesn't reorganize their layout.
    public static func serialize(_ config: YAMLConfig) throws -> String {
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
    /// noisy diffs. Comments are reinserted afterwards, so this pass only ever
    /// sees Yams output and never touches `#` lines.
    ///
    /// An item moves as a whole: its `- ` line and every line that continues it,
    /// so the second key of a mapping item stays under the first. Moving only the
    /// `- ` line turned `exclude_ranges: [{min: 1900, max: 2030}]` into
    /// `- max: 2030` over a `min: 1900` two columns to its left, which isn't YAML;
    /// SwiftLint then fell back to its default configuration. A line inside an item
    /// moves as far as the item's `- ` did; a new sequence moves two further than
    /// the item holding it, and a sibling item as far as the item before it.
    static func indentBlockSequences(in yaml: String) -> String {
        // Each item the current line may sit in: the original column of its `- `,
        // and how far that `- ` moved.
        var openItems: [(column: Int, shift: Int)] = []
        // The column of the line that opened a block scalar (`regex: |`) still running:
        // deeper lines are its text, moved with it, whatever they start with.
        var blockScalarColumn: Int?
        return yaml
            .components(separatedBy: .newlines)
            .map { line -> String in
                let trimmed = line.drop { $0 == " " }
                guard !trimmed.isEmpty else { return line }
                let column = line.count - trimmed.count
                if let block = blockScalarColumn, column > block {
                    return String(repeating: " ", count: openItems.last?.shift ?? 0) + line
                }
                blockScalarColumn = Self.opensBlockScalar(trimmed) ? column : nil
                // A line at or left of an item's `- ` is past that item. One exactly
                // at it starts a sibling, which moves as far as that item did.
                var sibling: (column: Int, shift: Int)?
                while let last = openItems.last, column <= last.column {
                    sibling = openItems.removeLast()
                }
                let dashes = Self.leadingSequenceDashes(in: trimmed)
                guard dashes > 0 else {
                    return String(repeating: " ", count: openItems.last?.shift ?? 0) + line
                }
                let shift = sibling?.column == column
                    ? sibling?.shift ?? 0
                    : (openItems.last?.shift ?? 0) + 2
                // `- - a` opens an item in an item; both move with the line.
                for index in 0..<dashes {
                    openItems.append((column: column + 2 * index, shift: shift))
                }
                return String(repeating: " ", count: shift) + line
            }
            .joined(separator: "\n")
    }

    /// Whether `line` (already stripped of indentation) ends in a block scalar header,
    /// `key: |`, `- >-` and the like, so the lines under it are text.
    private static func opensBlockScalar(_ line: Substring) -> Bool {
        guard let header = line.split(separator: " ").last,
              let indicator = header.first, indicator == "|" || indicator == ">" else { return false }
        let isHeader = header.dropFirst().allSatisfy { "+-0123456789".contains($0) }
        return isHeader && (line == header || line.hasSuffix(": " + header) || line.hasSuffix("- " + header))
    }

    /// How many sequence items `line` (already stripped of indentation) opens: one for
    /// `- a`, two for `- - a`.
    private static func leadingSequenceDashes(in line: Substring) -> Int {
        var count = 0
        var rest = line
        while rest == "-" || rest.hasPrefix("- ") {
            count += 1
            rest = rest.dropFirst(2)
        }
        return count
    }

    /// Build the ordered list of (key, value) pairs for the top-level mapping.
    ///
    /// Order priority:
    /// 1. Keys in `config.keyOrder` (preserves the user's original file layout)
    /// 2. Reserved SwiftLint keys not yet emitted, in `defaultTopLevelKeyOrder`
    /// 3. Per-rule configuration keys, alphabetically (stable output)
    private static func orderedTopLevelPairs(for config: YAMLConfig) throws -> [(Node, Node)] {
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
    private static func collectTopLevelKeyValues(from config: YAMLConfig) throws -> [String: Node] {
        var result: [String: Node] = [:]

        if let included = config.included { result["included"] = try Node(included) }
        if let excluded = config.excluded { result["excluded"] = try Node(excluded) }
        if let reporter = config.reporter { result["reporter"] = Node(reporter) }
        if let disabledRules = config.disabledRules, !disabledRules.isEmpty {
            result["disabled_rules"] = try Node(disabledRules)
        }
        if let optInRules = config.optInRules { result["opt_in_rules"] = try Node(optInRules) }
        if let analyzerRules = config.analyzerRules { result["analyzer_rules"] = try Node(analyzerRules) }
        if let onlyRules = config.onlyRules { result["only_rules"] = try Node(onlyRules) }

        // A disabled rule is expressed only via `disabled_rules`, never as a config
        // mapping. Verified against SwiftLint 0.65.0: a config carrying both emits
        // "Found a configuration for 'line_length' rule, but it is disabled in
        // 'disabled_rules'." in the user's own lint output. Note this means a rule's
        // severity/parameter overrides are dropped when it is disabled — that is the
        // cost of not provoking the warning, not an oversight.
        //
        // `disabled_rules` itself is emitted verbatim from `config.disabledRules`.
        // Do NOT fold `config.rules` entries with `enabled == false` into it: only
        // *default* rules are disabled that way. Opt-in and analyzer rules are
        // disabled by absence from `opt_in_rules` / `analyzer_rules`, and this layer
        // cannot tell which kind a rule is — `YAMLConfig` carries no rule metadata.
        // The callers that know the kind own that decision, through
        // YAMLConfig.disableRules(_:kind:).
        for (ruleId, ruleConfig) in config.rules where ruleConfig.enabled {
            if let node = try ruleNode(ruleId: ruleId, ruleConfig: ruleConfig, config: config) {
                result[ruleId] = node
            }
        }

        // Re-emit unmodeled top-level keys (custom_rules, etc.) exactly as parsed.
        for (key, node) in config.passthroughNodes where result[key] == nil {
            result[key] = node
        }

        return result
    }

    /// The serialized Node for one rule — a scalar for `line_length: 120`-style
    /// shorthand, otherwise a mapping. Returns nil for rules that emit nothing.
    private static func ruleNode(
        ruleId: String,
        ruleConfig: RuleConfiguration,
        config: YAMLConfig
    ) throws -> Node? {
        if config.scalarShorthandRules.contains(ruleId),
           let warning = Self.warningOnlyInt(for: ruleConfig) {
            return Node(String(warning), Tag(.int))
        }
        guard let value = topLevelRuleValue(for: ruleConfig) else { return nil }
        return try Node(value)
    }

    /// The warning threshold when `ruleConfig` is exactly a single `warning`
    /// integer (the scalar-shorthand shape); nil otherwise.
    private static func warningOnlyInt(for ruleConfig: RuleConfiguration) -> Int? {
        guard ruleConfig.severity == nil,
              let parameters = ruleConfig.parameters,
              parameters.count == 1,
              let warning = parameters["warning"]?.value as? Int else {
            return nil
        }
        return warning
    }

    /// Conventional emission order for reserved top-level SwiftLint keys when
    /// the loaded file didn't already provide an ordering for them.
    //
    // Mirror of the suppression on `modeledReservedKeys` (Parsing): the two lists overlap but
    // legitimately diverge, so Parallel List Drift reports a false positive. This list holds
    // passthrough keys (strict/lenient/warning_threshold) that get an emission position without
    // being modeled, and omits `rules`, which is migrated but never emitted.
    // swiftprojectlint:disable:next parallel-list-drift
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

    private static func topLevelRuleValue(for ruleConfig: RuleConfiguration) -> [String: Any]? {
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
