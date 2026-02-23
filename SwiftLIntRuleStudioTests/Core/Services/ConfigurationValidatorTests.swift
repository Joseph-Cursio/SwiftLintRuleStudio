//
//  ConfigurationValidatorTests.swift
//  SwiftLintRuleStudioTests
//
//  Unit tests for ConfigurationValidator
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

@MainActor
struct ConfigurationValidatorTests {
    // MARK: - Valid Configuration Tests

    @Test("Empty configuration is valid")
    func testEmptyConfigIsValid() {
        let validator = ConfigurationValidator()
        let config = YAMLConfigurationEngine.YAMLConfig()
        let result = validator.validate(config, knownRuleIds: [])

        #expect(result.isValid)
        #expect(result.errors.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test("Valid configuration with rules passes validation")
    func testValidConfigWithRules() {
        let validator = ConfigurationValidator()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules["force_cast"] = RuleConfiguration(enabled: true, severity: .warning)
        config.rules["line_length"] = RuleConfiguration(enabled: true, severity: .error)
        let result = validator.validate(config, knownRuleIds: ["force_cast", "line_length"])

        #expect(result.isValid)
        #expect(result.errors.isEmpty)
    }

    // MARK: - Severity Validation Tests

    @Test("Valid severity values pass validation")
    func testValidSeverityValues() {
        let validator = ConfigurationValidator()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules["rule1"] = RuleConfiguration(enabled: true, severity: .warning)
        config.rules["rule2"] = RuleConfiguration(enabled: true, severity: .error)
        let result = validator.validate(config, knownRuleIds: ["rule1", "rule2"])

        #expect(result.isValid)
        let severityErrors = result.errors.filter {
            if case .ruleSeverity = $0.field { return true }
            return false
        }
        #expect(severityErrors.isEmpty)
    }

    // MARK: - Path Validation Tests

    @Test("Empty included path fails validation")
    func testEmptyIncludedPathFails() {
        let validator = ConfigurationValidator()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.included = ["Sources", ""]
        let result = validator.validate(config, knownRuleIds: [])

        #expect(!result.isValid)
        #expect(result.errors.count == 1)

        let pathError = result.errors.first
        if case .includedPath(let index) = pathError?.field {
            #expect(index == 1)
        } else {
            Issue.record("Expected includedPath error")
        }
    }

    @Test("Empty excluded path fails validation")
    func testEmptyExcludedPathFails() {
        let validator = ConfigurationValidator()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.excluded = ["", "Pods"]
        let result = validator.validate(config, knownRuleIds: [])

        #expect(!result.isValid)
        #expect(result.errors.count == 1)

        let pathError = result.errors.first
        if case .excludedPath(let index) = pathError?.field {
            #expect(index == 0)
        } else {
            Issue.record("Expected excludedPath error")
        }
    }

    @Test("Valid paths pass validation")
    func testValidPathsPass() {
        let validator = ConfigurationValidator()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.included = ["Sources", "Tests"]
        config.excluded = ["Pods", "Carthage"]
        let result = validator.validate(config, knownRuleIds: [])

        #expect(result.isValid)
        #expect(result.errors.isEmpty)
    }

    // MARK: - Unknown Rule Warnings Tests

    @Test("Unknown rule ID generates warning")
    func testUnknownRuleIdWarning() {
        let validator = ConfigurationValidator()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules["unknown_rule"] = RuleConfiguration(enabled: true)
        let result = validator.validate(config, knownRuleIds: ["force_cast", "line_length"])

        #expect(result.isValid) // Warnings don't fail validation
        #expect(!result.warnings.isEmpty)
        #expect(result.warnings.first?.message.contains("Unknown") == true)
    }

    @Test("Unknown rule in disabled_rules generates warning")
    func testUnknownDisabledRuleWarning() {
        let validator = ConfigurationValidator()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["unknown_rule"]
        let result = validator.validate(config, knownRuleIds: ["force_cast"])

        #expect(result.isValid)
        #expect(!result.warnings.isEmpty)
    }

    @Test("Unknown rule in opt_in_rules generates warning")
    func testUnknownOptInRuleWarning() {
        let validator = ConfigurationValidator()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.optInRules = ["unknown_rule"]
        let result = validator.validate(config, knownRuleIds: ["force_cast"])

        #expect(result.isValid)
        #expect(!result.warnings.isEmpty)
    }

    // MARK: - Conflict Detection Tests

    @Test("Rule in both disabled and opt-in fails validation")
    func testConflictingRuleFails() {
        let validator = ConfigurationValidator()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["force_cast"]
        config.optInRules = ["force_cast"]
        let result = validator.validate(config, knownRuleIds: ["force_cast"])

        #expect(!result.isValid)
        #expect(result.errors.count == 1)
        #expect(result.errors.first?.message.contains("both disabled_rules and opt_in_rules") == true)
    }

    @Test("Different rules in disabled and opt-in passes validation")
    func testNoConflictPasses() {
        let validator = ConfigurationValidator()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["force_cast"]
        config.optInRules = ["line_length"]
        let result = validator.validate(config, knownRuleIds: ["force_cast", "line_length"])

        #expect(result.isValid)
        let conflictErrors = result.errors.filter {
            $0.message.contains("both disabled_rules and opt_in_rules")
        }
        #expect(conflictErrors.isEmpty)
    }

    // MARK: - Duplicate Detection Tests

    @Test("Duplicate rules in disabled_rules generates warning")
    func testDuplicateDisabledRulesWarning() {
        let validator = ConfigurationValidator()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["force_cast", "force_cast"]
        let result = validator.validate(config, knownRuleIds: ["force_cast"])

        #expect(result.isValid) // Duplicates are warnings, not errors
        #expect(result.warnings.contains { $0.message.contains("Duplicate") })
    }

    @Test("Duplicate rules in opt_in_rules generates warning")
    func testDuplicateOptInRulesWarning() {
        let validator = ConfigurationValidator()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.optInRules = ["line_length", "line_length", "force_cast"]
        let result = validator.validate(config, knownRuleIds: ["line_length", "force_cast"])

        #expect(result.isValid)
        #expect(result.warnings.contains { $0.message.contains("Duplicate") })
    }

    // MARK: - Parameter Validation Tests

    @Test("Negative parameter value generates warning")
    func testNegativeParameterWarning() {
        let validator = ConfigurationValidator()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules["line_length"] = RuleConfiguration(
            enabled: true,
            parameters: ["warning": AnyCodable(-10)]
        )
        let result = validator.validate(config, knownRuleIds: ["line_length"])

        #expect(result.isValid) // Parameter warnings don't fail validation
        #expect(result.warnings.contains { $0.message.contains("Negative") })
    }

    @Test("Empty string parameter generates warning")
    func testEmptyStringParameterWarning() {
        let validator = ConfigurationValidator()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules["custom_rule"] = RuleConfiguration(
            enabled: true,
            parameters: ["pattern": AnyCodable("")]
        )
        let result = validator.validate(config, knownRuleIds: ["custom_rule"])

        #expect(result.isValid)
        #expect(result.warnings.contains { $0.message.contains("Empty string") })
    }

    // MARK: - Similar Rule Suggestion Tests

    @Test("Suggests similar rule ID for typos")
    func testSuggestsSimilarRuleId() {
        let validator = ConfigurationValidator()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules["forc_cast"] = RuleConfiguration(enabled: true) // Typo
        let result = validator.validate(config, knownRuleIds: ["force_cast", "line_length"])

        #expect(result.isValid)
        let warning = result.warnings.first
        #expect(warning?.suggestion?.contains("force_cast") == true)
    }

    // MARK: - ConfigField Description Tests

    @Test("ConfigField descriptions are human-readable")
    func testConfigFieldDescriptions() {
        #expect(ValidationResult.ConfigField.rule("test").description == "Rule: test")
        #expect(ValidationResult.ConfigField.ruleSeverity("test").description == "Severity for: test")
        #expect(
            ValidationResult.ConfigField.ruleParameter("test", "param").description
            == "Parameter 'param' for: test"
        )
        #expect(ValidationResult.ConfigField.includedPath(0).description == "Included path #1")
        #expect(ValidationResult.ConfigField.excludedPath(2).description == "Excluded path #3")
        #expect(ValidationResult.ConfigField.disabledRules.description == "disabled_rules")
        #expect(ValidationResult.ConfigField.optInRules.description == "opt_in_rules")
        #expect(ValidationResult.ConfigField.general.description == "Configuration")
    }

    // MARK: - ValidationResult Tests

    @Test("ValidationResult.valid has correct properties")
    func testValidationResultValid() {
        let result = ValidationResult.valid

        #expect(result.isValid)
        #expect(result.errors.isEmpty)
        #expect(result.warnings.isEmpty)
    }
}
