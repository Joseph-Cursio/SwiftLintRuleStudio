//
//  UIAsyncTestHelpers.swift
//  SwiftLintRuleStudioTests
//

import SwiftLintCLIBackend
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import SwiftUI
import Testing
import ViewInspector

// Helpers for async test operations
enum UIAsyncTestHelpers {

    /// Waits for a condition to become true
    static func waitForCondition(
        timeout: TimeInterval = 1.0,
        interval: TimeInterval = 0.05,
        condition: () -> Bool
    ) async -> Bool {
        let startTime = Date.now
        while Date.now.timeIntervalSince(startTime) < timeout {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        return false
    }

    /// Waits for an async condition to become true
    static func waitForConditionAsync(
        timeout: TimeInterval = 1.0,
        interval: TimeInterval = 0.05,
        condition: () async -> Bool
    ) async -> Bool {
        let startTime = Date.now
        while Date.now.timeIntervalSince(startTime) < timeout {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        return false
    }

    /// Waits for a MainActor condition to become true
    @MainActor
    static func waitForConditionOnMainActor(
        timeout: TimeInterval = 1.0,
        interval: TimeInterval = 0.05,
        condition: () -> Bool
    ) async -> Bool {
        let startTime = Date.now
        while Date.now.timeIntervalSince(startTime) < timeout {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        return false
    }

    /// Waits for text to appear in a view
    @MainActor
    static func waitForText(
        in view: some View,
        text: String,
        timeout: TimeInterval = 1.0
    ) async -> Bool {
        await waitForConditionOnMainActor(timeout: timeout) {
            do {
                let inspectable = try view.inspect()
                return inspectable.containsText(text)
            } catch {
                return false
            }
        }
    }

    /// Waits for a view type to appear
    /// Note: Use concrete ViewType methods for better type safety
    static func waitForViewType<T>(
        in _: some View,
        _: T.Type,
        timeout: TimeInterval = 1.0
    ) async -> Bool {
        // This is a placeholder - use concrete ViewType methods in actual tests
        // For example: try view.inspect().find(ViewType.List.self)
        await waitForCondition(timeout: timeout) {
            // Use concrete find methods instead
            false
        }
    }
}
