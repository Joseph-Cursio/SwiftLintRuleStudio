//
//  ConfigurationValidatorOnlyRulesTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The validator's only_rules checks (issue #83): SwiftLint rejects only_rules beside
//  opt_in_rules or disabled_rules, and warns about ids also under analyzer_rules.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct ConfigurationValidatorOnlyRulesTests {
    @Test("only_rules beside opt_in_rules or disabled_rules fails validation")
    func testOnlyRulesConflictFails() {
        let validator = ConfigurationValidator()
        for (optIn, disabled) in [(["empty_count"], [String]()), ([], ["todo"])] {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.onlyRules = ["force_cast"]
            config.optInRules = optIn
            config.disabledRules = disabled
            let result = validator.validate(config, knownRuleIds: ["force_cast", "empty_count", "todo"])

            #expect(result.isValid == false)
            #expect(result.errors.contains { $0.field == .onlyRules })
        }
    }

    @Test("only_rules with empty opt_in_rules and disabled_rules passes validation")
    func testOnlyRulesWithEmptyListsPasses() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.onlyRules = ["force_cast"]
        config.optInRules = []
        config.disabledRules = []
        let result = ConfigurationValidator().validate(config, knownRuleIds: ["force_cast"])

        #expect(result.isValid)
    }

    @Test("A rule under both only_rules and analyzer_rules generates a warning")
    func testAnalyzerRuleInOnlyRulesWarns() {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.onlyRules = ["force_cast", "unused_import"]
        config.analyzerRules = ["unused_import"]
        let result = ConfigurationValidator().validate(config, knownRuleIds: ["force_cast", "unused_import"])

        #expect(result.isValid)
        #expect(result.warnings.filter { $0.field == .analyzerRules }.count == 1)
        #expect(result.warnings.first { $0.field == .analyzerRules }?.message.contains("unused_import") == true)
    }
}
