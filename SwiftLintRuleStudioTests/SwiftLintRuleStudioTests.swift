//
//  SwiftLintRuleStudioTests.swift
//  SwiftLintRuleStudioTests
//
//  Created by joe cursio on 12/24/25.
//

import Testing

// Main test suite - individual test files are organized by module
@MainActor
struct SwiftLintRuleStudioTests {

    @Test("Test suite is properly configured")
    func testSuiteConfiguration() {
        // Verify test infrastructure is working
        #expect(true)
    }
}

// MARK: - Shared Tags
// Use these tags to filter tests in Xcode Test Plans and the test navigator.
extension Tag {
    /// Tests that exercise filtering/search logic
    @Tag static var filtering: Self
    /// Tests that exercise ViolationStorageActor (SQLite persistence)
    @Tag static var storage: Self
    /// Tests that exercise ViewModel state and behavior
    @Tag static var viewModel: Self
}
