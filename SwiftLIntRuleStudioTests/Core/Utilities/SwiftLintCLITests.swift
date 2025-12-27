//
//  SwiftLintCLITests.swift
//  SwiftLintRuleStudioTests
//
//  Created by joe cursio on 12/24/25.
//

import Testing
@testable import SwiftLIntRuleStudio

struct SwiftLintCLITests {
    
    @Test("SwiftLintError has correct error descriptions")
    func testSwiftLintErrorDescriptions() {
        let notFoundError = SwiftLintError.notFound
        #expect(notFoundError.errorDescription?.contains("not found") == true)
        
        let invalidVersionError = SwiftLintError.invalidVersion
        #expect(invalidVersionError.errorDescription?.contains("version") == true)
        
        let executionError = SwiftLintError.executionFailed(message: "Test error")
        #expect(executionError.errorDescription?.contains("Test error") == true)
    }
    
    // Note: Actual CLI execution tests would require SwiftLint to be installed
    // These would be integration tests rather than unit tests
    // For now, we test the error types and structure
}

