//
//  RuleTests.swift
//  SwiftLintRuleStudioTests
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// Model tests don't need @MainActor - but Swift 6 false positive requires it temporarily
@MainActor
struct RuleTests {
    
    @Test("Rule can be created with all properties")
    func testRuleCreation() {
        let rule = Rule(
            id: "force_cast",
            name: "Force Cast",
            description: "Force casts should be avoided",
            category: .lint,
            isOptIn: false,
            severity: .error,
            parameters: nil,
            triggeringExamples: ["let x = y as! String"],
            nonTriggeringExamples: ["let x = y as? String"],
            documentation: nil
        )
        
        #expect(rule.id == "force_cast")
        #expect(rule.name == "Force Cast")
        #expect(rule.category == .lint)
        #expect(rule.isOptIn == false)
        #expect(rule.severity == .error)
    }
    
    @Test("RuleCategory has correct display names")
    func testRuleCategoryDisplayNames() {
        #expect(RuleCategory.style.displayName == "Style")
        #expect(RuleCategory.lint.displayName == "Lint")
        #expect(RuleCategory.metrics.displayName == "Metrics")
        #expect(RuleCategory.performance.displayName == "Performance")
        #expect(RuleCategory.idiomatic.displayName == "Idiomatic")
    }
    
    @Test("Severity has correct display names")
    func testSeverityDisplayNames() {
        #expect(Severity.warning.displayName == "Warning")
        #expect(Severity.error.displayName == "Error")
    }
    
    @Test("Rule is Codable")
    func testRuleCodable() throws {
        let rule = Rule(
            id: "test_rule",
            name: "Test Rule",
            description: "A test rule",
            category: .style,
            isOptIn: true,
            severity: .warning,
            parameters: nil,
            triggeringExamples: ["bad code"],
            nonTriggeringExamples: ["good code"],
            documentation: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(rule)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Rule.self, from: data)
        
        #expect(decoded.id == rule.id)
        #expect(decoded.name == rule.name)
        #expect(decoded.category == rule.category)
    }
}

