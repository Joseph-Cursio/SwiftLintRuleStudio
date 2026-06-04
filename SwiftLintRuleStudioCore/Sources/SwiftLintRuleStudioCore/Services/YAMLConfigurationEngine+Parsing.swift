import Foundation
import Yams

extension YAMLConfigurationEngine {
    /// Convert a YAML node into a Swift dictionary
    public func nodeToDictionary(_ node: Node) throws -> [String: Any] {
        guard case .mapping(let mapping) = node else {
            throw YAMLConfigError.parseError("Expected mapping node")
        }

        var dict: [String: Any] = [:]
        for (keyNode, valueNode) in mapping {
            guard let key = keyNode.string else {
                continue
            }
            dict[key] = try nodeToAny(valueNode)
        }
        return dict
    }

    private func nodeToAny(_ node: Node) throws -> Any {
        switch node {
        case .scalar(let scalar):
            return parseScalarValue(scalar)
        case .mapping:
            return try nodeToDictionary(node)
        case .sequence(let sequence):
            return try parseSequence(sequence)
        case .alias:
            return try nodeToDictionary(node)
        }
    }

    private func parseSequence(_ sequence: Node.Sequence) throws -> [Any] {
        var array: [Any] = []
        for item in sequence {
            array.append(try nodeToAny(item))
        }
        return array
    }

    private func parseScalarValue(_ scalar: Node.Scalar) -> Any {
        let stringValue = scalar.string
        let tagDescription = String(describing: scalar.tag)
        if isBoolScalar(tagDescription: tagDescription, stringValue: stringValue) {
            return stringValue == "true"
        }
        if isIntScalar(tagDescription: tagDescription) {
            return Int(stringValue) ?? stringValue
        }
        if isFloatScalar(tagDescription: tagDescription) {
            return Double(stringValue) ?? stringValue
        }
        // Plain (unquoted) scalars arrive without an explicit tag — Yams leaves
        // tag resolution to the consumer when you walk Nodes directly. Apply
        // YAML's implicit-resolution rules so unquoted numerics like `120`
        // round-trip as Int rather than String (otherwise re-serialization
        // emits them quoted, which SwiftLint rejects as invalid configuration).
        if scalar.style == .plain {
            if let intValue = Int(stringValue) {
                return intValue
            }
            if let doubleValue = Double(stringValue) {
                return doubleValue
            }
        }
        return stringValue
    }

    private func isBoolScalar(tagDescription: String, stringValue: String) -> Bool {
        if tagDescription.contains("bool") || tagDescription.contains("tag:yaml.org,2002:bool") {
            return true
        }
        return stringValue == "true" || stringValue == "false"
    }

    private func isIntScalar(tagDescription: String) -> Bool {
        tagDescription.contains("int") || tagDescription.contains("tag:yaml.org,2002:int")
    }

    private func isFloatScalar(tagDescription: String) -> Bool {
        tagDescription.contains("float") || tagDescription.contains("tag:yaml.org,2002:float")
    }

    /// Parse a dictionary into a SwiftLintConfiguration struct
    public func parseDictionaryToConfig(_ dict: [String: Any]) throws -> SwiftLintConfiguration {
        var config = SwiftLintConfiguration()
        parseReservedFields(from: dict, into: &config)
        parseLegacyRulesBlock(from: dict, into: &config)
        parseTopLevelRuleConfigurations(from: dict, into: &config)
        return config
    }

    private func parseReservedFields(from dict: [String: Any], into config: inout SwiftLintConfiguration) {
        config.included = dict["included"] as? [String]
        config.excluded = dict["excluded"] as? [String]
        config.reporter = dict["reporter"] as? String
        config.disabledRules = dict["disabled_rules"] as? [String]
        config.optInRules = dict["opt_in_rules"] as? [String]
        config.analyzerRules = dict["analyzer_rules"] as? [String]
        config.onlyRules = dict["only_rules"] as? [String]
    }

    // Tolerant read of the legacy `rules:` block (older versions of this app
    // emitted it; SwiftLint rejects it). Parsing it here lets those files
    // round-trip into the correct top-level layout on next save, and any
    // `enabled: false` entries get migrated into `disabled_rules`.
    private func parseLegacyRulesBlock(from dict: [String: Any], into config: inout SwiftLintConfiguration) {
        guard let rulesDict = dict["rules"] as? [String: Any] else { return }
        config.rules = parseRulesConfig(from: rulesDict)
        var migrated = config.disabledRules ?? []
        for (ruleId, ruleConfig) in config.rules where !ruleConfig.enabled {
            if !migrated.contains(ruleId) {
                migrated.append(ruleId)
            }
        }
        if !migrated.isEmpty {
            config.disabledRules = migrated
        }
    }

    // Any top-level key not in the reserved set is treated as a per-rule
    // configuration — that matches SwiftLint's actual schema.
    private func parseTopLevelRuleConfigurations(from dict: [String: Any], into config: inout SwiftLintConfiguration) {
        for (key, value) in dict where !Self.reservedTopLevelKeys.contains(key) {
            if let ruleConfig = parseRuleConfiguration(from: value) {
                config.rules[key] = ruleConfig
            }
        }
    }

    /// Top-level YAML keys SwiftLint recognizes as configuration rather than
    /// rule identifiers. Anything not in this set is read as a rule config.
    static let reservedTopLevelKeys: Set<String> = [
        "rules", // legacy app-emitted block, handled separately above
        "included",
        "excluded",
        "reporter",
        "disabled_rules",
        "opt_in_rules",
        "analyzer_rules",
        "only_rules",
        "whitelist_rules",
        "warning_threshold",
        "strict",
        "lenient",
        "cache_path",
        "swiftlint_version",
        "parent_config",
        "child_config",
        "remote_timeout",
        "remote_timeout_if_cached",
        "allow_zero_lintable_files",
        "treat_deprecated_as_warning",
        "force_exclude",
        "use_alternative_excluding",
        "use_nested_configs",
        "baseline",
        "write_baseline",
        "check_for_updates",
        "custom_rules"
    ]

    /// Reserved top-level keys the engine actively models (parses *and* emits).
    static let modeledReservedKeys: Set<String> = [
        "rules", "included", "excluded", "reporter",
        "disabled_rules", "opt_in_rules", "analyzer_rules", "only_rules"
    ]

    /// Captures the parsed YAML nodes for top-level keys the engine does not
    /// itself emit, so they survive a round-trip unchanged. This covers reserved
    /// keys we don't model (`custom_rules`, `warning_threshold`, …) *and* rule
    /// configs the engine can't parse into its model (e.g. the scalar shorthand
    /// `line_length: 120`, which isn't a bool or a mapping). `modeledKeys` is the
    /// set the modeled path will emit — every other top-level key passes through.
    static func passthroughNodes(from node: Node, modeledKeys: Set<String>) -> [String: Node] {
        guard case .mapping(let mapping) = node else { return [:] }
        var result: [String: Node] = [:]
        for (keyNode, valueNode) in mapping {
            guard let key = keyNode.string, !modeledKeys.contains(key) else { continue }
            result[key] = valueNode
        }
        return result
    }

    private func parseRulesConfig(from rulesDict: [String: Any]) -> [String: RuleConfiguration] {
        var rules: [String: RuleConfiguration] = [:]
        for (ruleId, ruleValue) in rulesDict {
            if let ruleConfig = parseRuleConfiguration(from: ruleValue) {
                rules[ruleId] = ruleConfig
            }
        }
        return rules
    }

    private func parseRuleConfiguration(from ruleValue: Any) -> RuleConfiguration? {
        if let boolValue = parseBoolRuleValue(from: ruleValue) {
            return RuleConfiguration(enabled: boolValue)
        }
        guard let ruleDict = ruleValue as? [String: Any] else {
            return nil
        }
        return parseComplexRuleConfiguration(from: ruleDict)
    }

    // Returns nil when the value isn't parseable as a boolean
    // swiftlint:disable:next discouraged_optional_boolean
    private func parseBoolRuleValue(from ruleValue: Any) -> Bool? {
        if let boolRuleValue = ruleValue as? Bool {
            return boolRuleValue
        }
        if let str = ruleValue as? String, str == "true" || str == "false" {
            return str == "true"
        }
        return nil
    }

    private func parseComplexRuleConfiguration(from ruleDict: [String: Any]) -> RuleConfiguration {
        let severity = parseSeverity(from: ruleDict)
        let enabled = parseEnabledValue(from: ruleDict)
        let parameters = parseRuleParameters(from: ruleDict)
        return RuleConfiguration(
            enabled: enabled,
            severity: severity,
            parameters: parameters
        )
    }

    private func parseSeverity(from ruleDict: [String: Any]) -> Severity? {
        guard let severityStr = ruleDict["severity"] as? String else {
            return nil
        }
        return Severity(rawValue: severityStr)
    }

    private func parseEnabledValue(from ruleDict: [String: Any]) -> Bool {
        if let enabledValue = ruleDict["enabled"] as? Bool {
            return enabledValue
        }
        if let enabledStr = ruleDict["enabled"] as? String {
            return enabledStr.lowercased() == "true"
        }
        return true
    }

    private func parseRuleParameters(from ruleDict: [String: Any]) -> [String: AnyCodable]? {
        var params: [String: AnyCodable] = [:]
        for (paramKey, paramValue) in ruleDict {
            if paramKey != "severity" && paramKey != "enabled" {
                params[paramKey] = AnyCodable(paramValue)
            }
        }
        return params.isEmpty ? nil : params
    }
}
