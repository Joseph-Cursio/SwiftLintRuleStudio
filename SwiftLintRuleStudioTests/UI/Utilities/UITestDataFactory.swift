//
//  UITestDataFactory.swift
//  SwiftLintRuleStudioTests
//

import Foundation
@testable import SwiftLintRuleStudioCore

// Factory methods for creating test data
// Using async functions with MainActor.run to allow parallel test execution
enum UITestDataFactory {

    // MARK: - Rule Factory

    /// Creates a test Rule with customizable properties
    static func createTestRule(
        id: String = "test_rule",
        name: String = "Test Rule",
        description: String = "Test description",
        category: RuleCategory = .lint,
        isOptIn: Bool = false,
        isEnabled: Bool = false,
        severity: Severity? = nil,
        parameters: [RuleParameter]? = nil,
        triggeringExamples: [String] = [],
        nonTriggeringExamples: [String] = [],
        documentation: URL? = nil,
        supportsAutocorrection: Bool = false,
        minimumSwiftVersion: String? = nil,
        defaultSeverity: Severity? = nil,
        markdownDocumentation: String? = nil
    ) -> Rule {
        Rule(
            id: id,
            name: name,
            description: description,
            category: category,
            isOptIn: isOptIn,
            severity: severity,
            parameters: parameters,
            triggeringExamples: triggeringExamples,
            nonTriggeringExamples: nonTriggeringExamples,
            documentation: documentation,
            isEnabled: isEnabled,
            supportsAutocorrection: supportsAutocorrection,
            minimumSwiftVersion: minimumSwiftVersion,
            defaultSeverity: defaultSeverity,
            markdownDocumentation: markdownDocumentation
        )
    }

    /// Creates multiple test rules
    static func createTestRules(count: Int, prefix: String = "test_rule") -> [Rule] {
        var rules: [Rule] = []
        for index in 0..<count {
            let rule = createTestRule(
                id: "\(prefix)_\(index)",
                name: "Test Rule \(index)",
                description: "Test description \(index)",
                category: index.isMultiple(of: 2) ? .lint : .style,
                isOptIn: index.isMultiple(of: 3),
                isEnabled: index.isMultiple(of: 2)
            )
            rules.append(rule)
        }
        return rules
    }

    // MARK: - Violation Factory

    /// Creates a test Violation with customizable properties
    static func createTestViolation(
        id: UUID = UUID(),
        ruleID: String = "test_rule",
        filePath: String = "Test.swift",
        line: Int = 10,
        column: Int? = 5,
        severity: Severity = .error,
        message: String = "Test violation message",
        detectedAt: Date = Date.now,
        resolvedAt: Date? = nil,
        suppressed: Bool = false,
        suppressionReason: String? = nil
    ) -> Violation {
        Violation(
            ruleID: ruleID,
            filePath: filePath,
            line: line,
            severity: severity,
            message: message,
            id: id,
            column: column,
            detectedAt: detectedAt,
            resolvedAt: resolvedAt,
            suppressed: suppressed,
            suppressionReason: suppressionReason
        )
    }

    /// Creates multiple test violations
    static func createTestViolations(
        count: Int,
        ruleID: String = "test_rule",
        filePath: String = "Test.swift"
    ) -> [Violation] {
        var violations: [Violation] = []
        for index in 0..<count {
            let violation = createTestViolation(
                ruleID: ruleID,
                filePath: filePath,
                line: index + 1,
                severity: index.isMultiple(of: 2) ? .error : .warning,
                message: "Test violation message \(index)"
            )
            violations.append(violation)
        }
        return violations
    }

    // MARK: - Workspace Factory

    /// Creates a test Workspace
    static func createTestWorkspace(
        name: String = "TestWorkspace",
        path: URL? = nil
    ) -> Workspace {
        let workspacePath = path ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("TestWorkspace_\(UUID().uuidString)", isDirectory: true)
        return Workspace(path: workspacePath, name: name)
    }
}
