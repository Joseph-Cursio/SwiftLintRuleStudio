import Foundation
import Yams

extension YAMLConfigurationEngine {
    /// Serialize a YAML configuration to a string
    public func serialize(_ config: YAMLConfig) throws -> String {
        // Convert to SwiftLintConfiguration for encoding
        var swiftLintConfig = SwiftLintConfiguration()
        swiftLintConfig.rules = config.rules
        swiftLintConfig.included = config.included
        swiftLintConfig.excluded = config.excluded
        swiftLintConfig.reporter = config.reporter

        // Encode to YAML using Yams
        do {
            // Convert to dictionary for Yams encoding
            let dict = configToDictionary(config)
            let node = try Node(dict)
            // Yams.serialize returns a String directly
            let yamlString = try Yams.serialize(node: node)

            // Reinsert comments if possible
            return reinsertComments(into: yamlString, config: config)
        } catch {
            throw YAMLConfigError.serializationError(error.localizedDescription)
        }
    }

    private func configToDictionary(_ config: YAMLConfig) -> [String: Any] {
        var dict: [String: Any] = [:]

        // Add SwiftLint reserved top-level keys
        if let included = config.included {
            dict["included"] = included
        }
        if let excluded = config.excluded {
            dict["excluded"] = excluded
        }
        if let reporter = config.reporter {
            dict["reporter"] = reporter
        }
        if let disabledRules = config.disabledRules {
            dict["disabled_rules"] = disabledRules
        }
        if let optInRules = config.optInRules {
            dict["opt_in_rules"] = optInRules
        }
        if let analyzerRules = config.analyzerRules {
            dict["analyzer_rules"] = analyzerRules
        }
        if let onlyRules = config.onlyRules {
            dict["only_rules"] = onlyRules
        }

        // Per-rule configuration (severity / parameters) goes as top-level
        // keys, matching SwiftLint's expected schema. Skip simple on/off
        // entries — those states are conveyed by the rule-list keys above.
        for (ruleId, ruleConfig) in config.rules {
            guard let value = topLevelRuleValue(for: ruleConfig) else { continue }
            dict[ruleId] = value
        }

        return dict
    }

    private func topLevelRuleValue(for ruleConfig: RuleConfiguration) -> Any? {
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
