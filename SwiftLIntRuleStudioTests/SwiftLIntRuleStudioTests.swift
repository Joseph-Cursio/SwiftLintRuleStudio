//
//  SwiftLIntRuleStudioTests.swift
//  SwiftLintRuleStudioTests
//
//  Created by joe cursio on 12/24/25.
//

import Testing
@testable import SwiftLIntRuleStudio

// MARK: - Shared Tags
// Use these tags to filter tests in Xcode Test Plans and the test navigator.
extension Tag {
    /// Tests that exercise filtering/search logic
    @Tag static var filtering: Self
    /// Tests that exercise ViolationStorage (SQLite persistence)
    @Tag static var storage: Self
    /// Tests that exercise ImpactSimulator rule simulation
    @Tag static var simulation: Self
    /// Tests that exercise ViewModel state and behavior
    @Tag static var viewModel: Self
    /// Tests that exercise SwiftUI view structure
    @Tag static var ui: Self
    /// Tests that wire real service implementations together
    @Tag static var integration: Self
}

// Main test suite - individual test files are organized by module
struct SwiftLIntRuleStudioTests {
    
    @Test("Test suite is properly configured")
    func testSuiteConfiguration() {
        // Verify test infrastructure is working
        #expect(true)
    }
}
