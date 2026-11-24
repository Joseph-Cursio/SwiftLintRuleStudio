//
//  RuleAuditViewTests+Fixtures.swift
//  SwiftLintRuleStudioTests
//
//  The workspace, rules and audit entries RuleAuditViewTests runs against
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI

extension RuleAuditViewTests {
    /// A temporary workspace with one Swift file and a config that disables the two safe rules.
    static func makeAuditWorkspace() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuleAuditViewTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let swiftFile = tempDir.appendingPathComponent("Test.swift")
        try Data("struct Test {}".utf8).write(to: swiftFile)

        let configURL = tempDir.appendingPathComponent(".swiftlint.yml")
        let configContent = """
        disabled_rules:
          - safe_rule_1
          - safe_rule_2
        rules:
          some_other_rule:
            enabled: false
        """
        try Data(configContent.utf8).write(to: configURL)
        return tempDir
    }

    /// A default lint rule that is currently disabled.
    static func disabledRule(id: String, name: String) -> Rule {
        Rule(
            id: id,
            name: name,
            description: "desc",
            category: .lint,
            isOptIn: false,
            severity: nil,
            parameters: nil,
            triggeringExamples: [],
            nonTriggeringExamples: [],
            documentation: nil,
            isEnabled: false,
            supportsAutocorrection: false,
            minimumSwiftVersion: nil,
            defaultSeverity: nil,
            markdownDocumentation: nil
        )
    }

    /// A simulation of `ruleId` that found no violations.
    static func cleanResult(ruleId: String) -> RuleImpactResult {
        RuleImpactResult(
            ruleId: ruleId,
            violationCount: 0,
            violations: [],
            affectedFiles: [],
            simulationDuration: 0.1
        )
    }

    /// A safe rule, a low-effort rule and an already-enabled rule.
    static func sampleEntries() -> [RuleAuditEntry] {
        [
            RuleAuditEntry(
                rule: Rule(
                    id: "safe_rule",
                    name: "Safe Rule",
                    description: "A safe rule",
                    category: .lint,
                    isOptIn: false,
                    supportsAutocorrection: true
                ),
                impactResult: RuleImpactResult(
                    ruleId: "safe_rule",
                    violationCount: 0,
                    violations: [],
                    affectedFiles: [],
                    simulationDuration: 0.1
                ),
                isCurrentlyEnabled: false
            ),
            RuleAuditEntry(
                rule: Rule(
                    id: "low_rule",
                    name: "Low Rule",
                    description: "A low effort rule",
                    category: .style,
                    isOptIn: false,
                    supportsAutocorrection: false
                ),
                impactResult: RuleImpactResult(
                    ruleId: "low_rule",
                    violationCount: 3,
                    violations: [],
                    affectedFiles: ["file1.swift"],
                    simulationDuration: 0.2
                ),
                isCurrentlyEnabled: false
            ),
            RuleAuditEntry(
                rule: Rule(
                    id: "enabled_rule",
                    name: "Enabled Rule",
                    description: "Already enabled",
                    category: .metrics,
                    isOptIn: false
                ),
                impactResult: nil,
                isCurrentlyEnabled: true
            ),
        ]
    }

    /// Whether `text` appears in `view` within three seconds.
    static func waitForText(_ text: String, in view: some View) async -> Bool {
        await UIAsyncTestHelpers.waitForText(in: view, text: text, timeout: 3.0)
    }
}
