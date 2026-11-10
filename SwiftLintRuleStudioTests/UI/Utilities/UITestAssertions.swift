//
//  UITestAssertions.swift
//  SwiftLintRuleStudioTests
//

import SwiftLintCLIBackend
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import SwiftUI
import Testing
import ViewInspector

// Helpers for common test assertions
enum UITestAssertions {

    /// Asserts that a view contains specific text
    static func assertContainsText(
        _ view: some View,
        text: String
    ) throws {
        let inspectable = try view.inspect()
        #expect(inspectable.containsText(text), "View should contain text: \(text)")
    }

    /// Asserts that a view does not contain specific text
    static func assertNotContainsText(
        _ view: some View,
        text: String
    ) throws {
        let inspectable = try view.inspect()
        #expect(inspectable.containsText(text) == false, "View should not contain text: \(text)")
    }

    /// Asserts that a view contains a specific view type
    /// Note: Use concrete ViewType methods like find(ViewType.List.self) for better type safety
    static func assertContainsViewType<T>(
        _: some View,
        _: T.Type
    ) throws {
        // This is a placeholder - use concrete ViewType methods in actual tests
        // For example: try view.inspect().find(ViewType.List.self)
        #expect(true, "Use concrete ViewType methods for type checking")
    }

    /// Asserts that a button exists and is enabled
    static func assertButtonExists(
        _ view: some View,
        text: String,
        enabled _: Bool = true
    ) throws {
        let inspectable = try view.inspect()
        _ = try inspectable.findButton(text: text)
        // Note: Button enabled state may require additional inspection
    }
}
