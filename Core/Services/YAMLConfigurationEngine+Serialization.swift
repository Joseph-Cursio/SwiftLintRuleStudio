import Foundation
import Yams

extension YAMLConfigurationEngine {
    func serialize(_ config: YAMLConfig) throws -> String {
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
        
        // Add rules
        if !config.rules.isEmpty {
            dict["rules"] = buildRulesDictionary(from: config.rules)
        }
        
        // Add other fields
        if let included = config.included {
            dict["included"] = included
        }
        if let excluded = config.excluded {
            dict["excluded"] = excluded
        }
        if let reporter = config.reporter {
            dict["reporter"] = reporter
        }
        
        return dict
    }
    
    private func buildRulesDictionary(from rules: [String: RuleConfiguration]) -> [String: Any] {
        var rulesDict: [String: Any] = [:]
        for (ruleId, ruleConfig) in rules {
            rulesDict[ruleId] = ruleDictionaryValue(for: ruleConfig)
        }
        return rulesDict
    }
    
    private func ruleDictionaryValue(for ruleConfig: RuleConfiguration) -> Any {
        if isSimpleBooleanRule(ruleConfig, enabled: true) {
            return true
        }
        if isSimpleBooleanRule(ruleConfig, enabled: false) {
            return false
        }
        
        var ruleDict: [String: Any] = [:]
        if let severity = ruleConfig.severity {
            ruleDict["severity"] = severity.rawValue
        }
        if let parameters = ruleConfig.parameters {
            for (key, value) in parameters {
                ruleDict[key] = value.value
            }
        }
        if !ruleConfig.enabled {
            ruleDict["enabled"] = false
        }
        return ruleDict
    }
    
    private func isSimpleBooleanRule(_ ruleConfig: RuleConfiguration, enabled: Bool) -> Bool {
        ruleConfig.severity == nil && ruleConfig.parameters == nil && ruleConfig.enabled == enabled
    }
}
