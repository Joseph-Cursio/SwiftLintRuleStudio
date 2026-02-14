//
//  ConfigurationValidator.swift
//  SwiftLintRuleStudio
//
//  Real-time validation service for SwiftLint configuration
//

import Foundation

/// Result of configuration validation
struct ValidationResult: Sendable {
    let isValid: Bool
    let errors: [ValidationError]
    let warnings: [ValidationWarning]

    /// A validation error that prevents the configuration from being saved
    struct ValidationError: Identifiable, Sendable {
        let id = UUID()
        let field: ConfigField
        let message: String
        let suggestion: String?

        init(field: ConfigField, message: String, suggestion: String? = nil) {
            self.field = field
            self.message = message
            self.suggestion = suggestion
        }
    }

    /// A validation warning that doesn't prevent saving but indicates potential issues
    struct ValidationWarning: Identifiable, Sendable {
        let id = UUID()
        let field: ConfigField
        let message: String
        let suggestion: String?

        init(field: ConfigField, message: String, suggestion: String? = nil) {
            self.field = field
            self.message = message
            self.suggestion = suggestion
        }
    }

    /// Identifies which field in the configuration has an issue
    enum ConfigField: Hashable, Sendable {
        case rule(String)
        case ruleSeverity(String)
        case ruleParameter(String, String)
        case includedPath(Int)
        case excludedPath(Int)
        case disabledRules
        case optInRules
        case general

        var description: String {
            switch self {
            case .rule(let ruleId):
                return "Rule: \(ruleId)"
            case .ruleSeverity(let ruleId):
                return "Severity for: \(ruleId)"
            case .ruleParameter(let ruleId, let param):
                return "Parameter '\(param)' for: \(ruleId)"
            case .includedPath(let index):
                return "Included path #\(index + 1)"
            case .excludedPath(let index):
                return "Excluded path #\(index + 1)"
            case .disabledRules:
                return "disabled_rules"
            case .optInRules:
                return "opt_in_rules"
            case .general:
                return "Configuration"
            }
        }
    }

    static var valid: ValidationResult {
        ValidationResult(isValid: true, errors: [], warnings: [])
    }
}

/// Protocol for configuration validation
@MainActor
protocol ConfigurationValidatorProtocol {
    /// Validate a configuration and return detailed results
    func validate(_ config: YAMLConfigurationEngine.YAMLConfig) -> ValidationResult

    /// Validate a configuration against known rule IDs
    func validate(
        _ config: YAMLConfigurationEngine.YAMLConfig,
        knownRuleIds: Set<String>
    ) -> ValidationResult
}

/// Service for validating SwiftLint configurations in real-time
@MainActor
class ConfigurationValidator: ConfigurationValidatorProtocol {
    private let ruleRegistry: RuleRegistry?

    init(ruleRegistry: RuleRegistry? = nil) {
        self.ruleRegistry = ruleRegistry
    }

    /// Validate a configuration and return detailed results
    func validate(_ config: YAMLConfigurationEngine.YAMLConfig) -> ValidationResult {
        let knownRuleIds = Set(ruleRegistry?.rules.map(\.id) ?? [])
        return validate(config, knownRuleIds: knownRuleIds)
    }

    /// Validate a configuration against known rule IDs
    func validate(
        _ config: YAMLConfigurationEngine.YAMLConfig,
        knownRuleIds: Set<String>
    ) -> ValidationResult {
        var errors: [ValidationResult.ValidationError] = []
        var warnings: [ValidationResult.ValidationWarning] = []

        // Validate rule configurations
        validateRules(config.rules, knownRuleIds: knownRuleIds, errors: &errors, warnings: &warnings)

        // Validate included paths
        validatePaths(config.included, isIncluded: true, errors: &errors)

        // Validate excluded paths
        validatePaths(config.excluded, isIncluded: false, errors: &errors)

        // Validate disabled_rules
        validateRuleList(
            config.disabledRules,
            fieldType: .disabledRules,
            knownRuleIds: knownRuleIds,
            errors: &errors,
            warnings: &warnings
        )

        // Validate opt_in_rules
        validateRuleList(
            config.optInRules,
            fieldType: .optInRules,
            knownRuleIds: knownRuleIds,
            errors: &errors,
            warnings: &warnings
        )

        // Check for conflicting rules (in both disabled and opt-in)
        validateNoConflicts(config, errors: &errors)

        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    // MARK: - Private Validation Methods

    private func validateRules(
        _ rules: [String: RuleConfiguration],
        knownRuleIds: Set<String>,
        errors: inout [ValidationResult.ValidationError],
        warnings: inout [ValidationResult.ValidationWarning]
    ) {
        for (ruleId, ruleConfig) in rules {
            // Check for unknown rule IDs
            if !knownRuleIds.isEmpty && !knownRuleIds.contains(ruleId) {
                warnings.append(ValidationResult.ValidationWarning(
                    field: .rule(ruleId),
                    message: "Unknown rule identifier",
                    suggestion: findSimilarRuleId(ruleId, in: knownRuleIds)
                        .map { "Did you mean '\($0)'?" }
                ))
            }

            // Validate severity
            if let severity = ruleConfig.severity {
                if severity != .warning && severity != .error {
                    errors.append(ValidationResult.ValidationError(
                        field: .ruleSeverity(ruleId),
                        message: "Invalid severity: \(severity.rawValue)",
                        suggestion: "Use 'warning' or 'error'"
                    ))
                }
            }

            // Validate parameters
            if let parameters = ruleConfig.parameters {
                for (paramName, paramValue) in parameters {
                    validateParameter(
                        ruleId: ruleId,
                        paramName: paramName,
                        paramValue: paramValue,
                        errors: &errors,
                        warnings: &warnings
                    )
                }
            }
        }
    }

    private func validateParameter(
        ruleId: String,
        paramName: String,
        paramValue: AnyCodable,
        errors: inout [ValidationResult.ValidationError],
        warnings: inout [ValidationResult.ValidationWarning]
    ) {
        // Check for common parameter issues
        if let intValue = paramValue.value as? Int, intValue < 0 {
            warnings.append(ValidationResult.ValidationWarning(
                field: .ruleParameter(ruleId, paramName),
                message: "Negative value may not be valid for this parameter",
                suggestion: "Consider using a positive value"
            ))
        }

        if let stringValue = paramValue.value as? String, stringValue.isEmpty {
            warnings.append(ValidationResult.ValidationWarning(
                field: .ruleParameter(ruleId, paramName),
                message: "Empty string parameter",
                suggestion: "Consider removing or providing a value"
            ))
        }
    }

    private func validatePaths(
        _ paths: [String]?,
        isIncluded: Bool,
        errors: inout [ValidationResult.ValidationError]
    ) {
        guard let paths = paths else { return }

        for (index, path) in paths.enumerated() {
            let field: ValidationResult.ConfigField = isIncluded
                ? .includedPath(index)
                : .excludedPath(index)

            if path.isEmpty {
                errors.append(ValidationResult.ValidationError(
                    field: field,
                    message: "Empty path",
                    suggestion: "Provide a valid path or remove this entry"
                ))
            }

            // Check for potentially problematic patterns
            if path.hasPrefix("/") && !FileManager.default.fileExists(atPath: path) {
                // Only warn for absolute paths that don't exist
                // Relative paths are expected to be resolved against workspace
            }
        }
    }

    private func validateRuleList(
        _ ruleIds: [String]?,
        fieldType: ValidationResult.ConfigField,
        knownRuleIds: Set<String>,
        errors: inout [ValidationResult.ValidationError],
        warnings: inout [ValidationResult.ValidationWarning]
    ) {
        guard let ruleIds = ruleIds, !knownRuleIds.isEmpty else { return }

        for ruleId in ruleIds {
            if !knownRuleIds.contains(ruleId) {
                warnings.append(ValidationResult.ValidationWarning(
                    field: fieldType,
                    message: "Unknown rule '\(ruleId)'",
                    suggestion: findSimilarRuleId(ruleId, in: knownRuleIds)
                        .map { "Did you mean '\($0)'?" }
                ))
            }
        }

        // Check for duplicates
        let uniqueIds = Set(ruleIds)
        if uniqueIds.count != ruleIds.count {
            warnings.append(ValidationResult.ValidationWarning(
                field: fieldType,
                message: "Duplicate rule IDs detected",
                suggestion: "Remove duplicate entries"
            ))
        }
    }

    private func validateNoConflicts(
        _ config: YAMLConfigurationEngine.YAMLConfig,
        errors: inout [ValidationResult.ValidationError]
    ) {
        guard let disabledRules = config.disabledRules,
              let optInRules = config.optInRules else { return }

        let disabledSet = Set(disabledRules)
        let optInSet = Set(optInRules)
        let conflicts = disabledSet.intersection(optInSet)

        for conflictingRule in conflicts {
            errors.append(ValidationResult.ValidationError(
                field: .rule(conflictingRule),
                message: "Rule appears in both disabled_rules and opt_in_rules",
                suggestion: "Remove from one of the lists"
            ))
        }
    }

    /// Find a similar rule ID using Levenshtein distance
    private func findSimilarRuleId(_ unknown: String, in knownIds: Set<String>) -> String? {
        var bestMatch: String?
        var bestDistance = Int.max

        for knownId in knownIds {
            let distance = levenshteinDistance(unknown, knownId)
            // Only suggest if distance is reasonable (less than half the string length)
            if distance < bestDistance && distance < max(unknown.count, knownId.count) / 2 {
                bestDistance = distance
                bestMatch = knownId
            }
        }

        return bestMatch
    }

    /// Calculate Levenshtein edit distance between two strings
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost  // substitution
                )
            }
        }

        return matrix[m][n]
    }
}
