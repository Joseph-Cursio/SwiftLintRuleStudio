//
//  ViolationTests.swift
//  SwiftLintRuleStudioTests
//
//  Created by joe cursio on 12/24/25.
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

// Model tests don't need @MainActor - but Swift 6 false positive requires it temporarily
@MainActor
struct ViolationTests {
    
    @Test("Violation can be created with required properties")
    func testViolationCreation() {
        let violation = Violation(
            ruleID: "force_cast",
            filePath: "/path/to/file.swift",
            line: 42,
            column: 10,
            severity: .error,
            message: "Force casts should be avoided"
        )
        
        #expect(violation.ruleID == "force_cast")
        #expect(violation.filePath == "/path/to/file.swift")
        #expect(violation.line == 42)
        #expect(violation.column == 10)
        #expect(violation.severity == .error)
        #expect(violation.suppressed == false)
    }
    
    @Test("Violation can be suppressed")
    func testViolationSuppression() {
        var violation = Violation(
            ruleID: "test_rule",
            filePath: "/path/to/file.swift",
            line: 1,
            severity: .warning,
            message: "Test message"
        )
        
        violation.suppressed = true
        violation.suppressionReason = "Legacy code"
        
        #expect(violation.suppressed == true)
        #expect(violation.suppressionReason == "Legacy code")
    }
    
    @Test("ViolationFilter has all option")
    func testViolationFilterAll() {
        let filter = ViolationFilter.all
        
        #expect(filter.ruleIDs == nil)
        #expect(filter.filePaths == nil)
        #expect(filter.suppressedOnly == nil)
    }
    
    @Test("Violation is Codable")
    func testViolationCodable() throws {
        let violation = Violation(
            ruleID: "test_rule",
            filePath: "/path/to/file.swift",
            line: 10,
            severity: .error,
            message: "Test violation"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(violation)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Violation.self, from: data)
        
        #expect(decoded.ruleID == violation.ruleID)
        #expect(decoded.filePath == violation.filePath)
        #expect(decoded.line == violation.line)
    }
}
