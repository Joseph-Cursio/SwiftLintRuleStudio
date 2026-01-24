import Foundation
import Yams

extension YAMLConfigurationEngine {
    func nodeToDictionary(_ node: Node) throws -> [String: Any] {
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
    
    func parseDictionaryToConfig(_ dict: [String: Any]) throws -> SwiftLintConfiguration {
        var config = SwiftLintConfiguration()
        
        // Parse rules
        if let rulesDict = dict["rules"] as? [String: Any] {
            config.rules = parseRulesConfig(from: rulesDict)
        }
        
        // Parse other fields
        if let included = dict["included"] as? [String] {
            config.included = included
        }
        if let excluded = dict["excluded"] as? [String] {
            config.excluded = excluded
        }
        if let reporter = dict["reporter"] as? String {
            config.reporter = reporter
        }
        
        return config
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
