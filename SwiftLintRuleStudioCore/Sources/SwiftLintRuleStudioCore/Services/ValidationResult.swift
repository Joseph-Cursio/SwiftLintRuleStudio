//
//  ValidationResult.swift
//  SwiftLintRuleStudio
//
//  The outcome of validating a SwiftLint configuration
//

import Foundation

/// Result of configuration validation
public struct ValidationResult: Sendable {
    public let isValid: Bool
    public let errors: [ValidationError]
    public let warnings: [ValidationWarning]

    public init(isValid: Bool, errors: [ValidationError], warnings: [ValidationWarning]) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }

    /// A validation error that prevents the configuration from being saved
    public struct ValidationError: Identifiable, Sendable {
        public let id = UUID()
        public let field: ConfigField
        public let message: String
        public let suggestion: String?

        public init(field: ConfigField, message: String, suggestion: String? = nil) {
            self.field = field
            self.message = message
            self.suggestion = suggestion
        }
    }

    /// A validation warning that doesn't prevent saving but indicates potential issues
    public struct ValidationWarning: Identifiable, Sendable {
        public let id = UUID()
        public let field: ConfigField
        public let message: String
        public let suggestion: String?

        public init(field: ConfigField, message: String, suggestion: String? = nil) {
            self.field = field
            self.message = message
            self.suggestion = suggestion
        }
    }

    /// Identifies which field in the configuration has an issue
    public enum ConfigField: Hashable, Sendable {
        case rule(String)
        case ruleSeverity(String)
        case ruleParameter(String, String)
        case includedPath(Int)
        case excludedPath(Int)
        case disabledRules
        case optInRules
        case onlyRules
        case analyzerRules
        case general

        public var description: String {
            switch self {
            case .rule(let ruleId):
                return "Rule: \(ruleId)"

            case .ruleSeverity(let ruleId):
                return "Severity for: \(ruleId)"

            case let .ruleParameter(ruleId, param):
                return "Parameter '\(param)' for: \(ruleId)"

            case .includedPath(let index):
                return "Included path #\(index + 1)"

            case .excludedPath(let index):
                return "Excluded path #\(index + 1)"

            case .disabledRules:
                return "disabled_rules"

            case .optInRules:
                return "opt_in_rules"

            case .onlyRules:
                return "only_rules"

            case .analyzerRules:
                return "analyzer_rules"

            case .general:
                return "Configuration"
            }
        }
    }

    public static var valid: Self {
        Self(isValid: true, errors: [], warnings: [])
    }
}
