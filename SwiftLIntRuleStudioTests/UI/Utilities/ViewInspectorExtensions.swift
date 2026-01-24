//
//  ViewInspectorExtensions.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector extensions for common test patterns
//

import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

private struct InspectableViewWrapper<ViewType: ViewInspector.BaseViewType>: @unchecked Sendable {
    let view: InspectableView<ViewType>
}

// MARK: - ViewInspector Extensions

// Extension for InspectableView to add common interaction helpers
// Note: This extension works with any InspectableView that can find text and buttons
extension InspectableView {
    
    /// Finds and taps a button by its text label
    /// - Parameter text: The button text to find
    /// - Throws: If button cannot be found
    func tapButton(text: String) throws {
        let buttonText = try find(text: text)
        let button = try buttonText.parent().find(ViewType.Button.self)
        try button.tap()
    }
    
    /// Finds a button by its text label
    /// - Parameter text: The button text to find
    /// - Returns: The button view
    /// - Throws: If button cannot be found
    func findButton(text: String) throws -> InspectableView<ViewType.Button> {
        let buttonText = try find(text: text)
        return try buttonText.parent().find(ViewType.Button.self)
    }
    
    /// Finds a text field and sets its input value
    /// - Parameters:
    ///   - input: The text to enter
    ///   - index: Optional index if multiple text fields exist (default: 0)
    /// - Throws: If text field cannot be found
    func setTextFieldInput(_ input: String, at index: Int = 0) throws {
        let textField = try findAll(ViewType.TextField.self)[index]
        try textField.setInput(input)
    }
    
    /// Finds a text field and gets its input value
    /// - Parameter index: Optional index if multiple text fields exist (default: 0)
    /// - Returns: The current input value
    /// - Throws: If text field cannot be found
    func getTextFieldInput(at index: Int = 0) throws -> String {
        let textField = try findAll(ViewType.TextField.self)[index]
        return try textField.input()
    }
    
    /// Finds a text field by placeholder text
    /// - Parameter placeholder: The placeholder text to find
    /// - Returns: The text field view
    /// - Throws: If text field cannot be found
    func findTextField(placeholder: String) throws -> InspectableView<ViewType.TextField> {
        // Note: ViewInspector may not directly support placeholder search
        // This is a helper that attempts to find by searching for text fields
        // and checking their attributes
        let textFields = try findAll(ViewType.TextField.self)
        // For now, return first text field - can be enhanced if needed
        return textFields[0]
    }
    
    /// Verifies that text exists in the view
    /// - Parameter text: The text to search for
    /// - Returns: True if text is found, false otherwise
    func containsText(_ text: String) -> Bool {
        do {
            _ = try find(text: text)
            return true
        } catch {
            return false
        }
    }
    
    /// Verifies that a view type exists
    /// - Parameter viewType: The view type to search for
    /// - Returns: True if view type is found, false otherwise
    /// Note: This is a generic helper - specific view types should use their concrete find methods
    func containsViewType<T>(_ viewType: T.Type) -> Bool {
        // This is a placeholder - specific implementations should use concrete ViewType methods
        // For example: find(ViewType.List.self), find(ViewType.Button.self), etc.
        return false
    }
    
    /// Finds a navigation link by its label text
    /// - Parameter text: The navigation link label text
    /// - Returns: The navigation link view
    /// - Throws: If navigation link cannot be found
    func findNavigationLink(text: String) throws -> InspectableView<ViewType.NavigationLink> {
        let linkText = try find(text: text)
        return try linkText.parent().find(ViewType.NavigationLink.self)
    }
    
    /// Taps a navigation link by its label text
    /// - Parameter text: The navigation link label text
    /// - Throws: If navigation link cannot be found
    func tapNavigationLink(text: String) throws {
        let link = try findNavigationLink(text: text)
        try link.activate()
    }
    
    /// Finds a picker by its selection binding or label
    /// - Parameter label: Optional label text to find the picker
    /// - Returns: The picker view
    /// - Throws: If picker cannot be found
    func findPicker(label: String? = nil) throws -> InspectableView<ViewType.Picker> {
        if let label = label {
            // Try to find by label
            let labelText = try find(text: label)
            return try labelText.parent().find(ViewType.Picker.self)
        } else {
            // Return first picker found
            return try find(ViewType.Picker.self)
        }
    }
    
    /// Waits for a view to appear (useful for async state changes)
    /// - Parameters:
    ///   - text: The text to wait for
    ///   - timeout: Maximum time to wait in nanoseconds (default: 1 second)
    /// - Returns: True if text appears, false if timeout
    func waitForText(_ text: String, timeout: UInt64 = 1_000_000_000) async -> Bool {
        let wrapper = InspectableViewWrapper(view: self)
        return await UIAsyncTestHelpers.waitForConditionAsync(
            timeout: TimeInterval(timeout) / 1_000_000_000,
            interval: 0.05
        ) {
            await MainActor.run {
                wrapper.view.containsText(text)
            }
        }
    }
}

// Note: View.inspect() is already provided by ViewInspector
// No need to extend it here

// MARK: - View Type Helpers

// Common view types for easier reference
enum CommonViewType {
    case list
    case button
    case textField
    case navigationLink
    case picker
    case vStack
    case hStack
    case navigationSplitView
    case navigationStack
}
