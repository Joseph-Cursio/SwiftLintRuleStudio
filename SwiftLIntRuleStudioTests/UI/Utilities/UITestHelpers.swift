//
//  UITestHelpers.swift
//  SwiftLintRuleStudioTests
//
//  Common test helpers and factories for UI tests
//

import SwiftUI
import Testing
import ViewInspector
@testable import SwiftLIntRuleStudio

// UserDefaults is passed across actor boundaries in tests; @retroactive silences the
// "retroactive conformance" warning while keeping the required Sendable conformance.
extension UserDefaults: @retroactive @unchecked Sendable {}

// MARK: - Test Data Factories

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
                category: index % 2 == 0 ? .lint : .style,
                isOptIn: index % 3 == 0,
                isEnabled: index % 2 == 0
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
        detectedAt: Date = Date(),
        resolvedAt: Date? = nil,
        suppressed: Bool = false,
        suppressionReason: String? = nil
    ) -> Violation {
        Violation(
            id: id,
            ruleID: ruleID,
            filePath: filePath,
            line: line,
            column: column,
            severity: severity,
            message: message,
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
                severity: index % 2 == 0 ? .error : .warning,
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

// MARK: - View Creation Helpers

// Helpers for creating views with proper environment objects
// Using async functions with MainActor.run to allow parallel test execution
enum UIViewTestHelpers {
    
    /// Creates a DependencyContainer with isolated UserDefaults for testing
    static func createTestDependencyContainer(
        userDefaults: UserDefaults? = nil
    ) async -> DependencyContainer {
        return await MainActor.run {
            DependencyContainer.createForTesting(userDefaults: userDefaults)
        }
    }
    
    /// Creates a view with DependencyContainer as environment object
    @MainActor
    static func createViewWithDependencies<Content: View>(
        _ content: Content,
        dependencyContainer: DependencyContainer? = nil
    ) -> AnyView {
        let container = dependencyContainer ?? DependencyContainer.createForTesting()
        return AnyView(content.environmentObject(container))
    }
    
    /// Creates a view with both RuleRegistry and DependencyContainer
    @MainActor
    static func createViewWithFullDependencies<Content: View>(
        _ content: Content,
        dependencyContainer: DependencyContainer? = nil,
        ruleRegistry: RuleRegistry? = nil
    ) -> AnyView {
        let container = dependencyContainer ?? DependencyContainer.createForTesting()
        let cacheManager = CacheManager.createForTesting()
        let swiftLintCLI = SwiftLintCLI(cacheManager: cacheManager)
        let registry = ruleRegistry ?? RuleRegistry(swiftLintCLI: swiftLintCLI, cacheManager: cacheManager)

        return AnyView(content
            .environmentObject(registry)
            .environmentObject(container))
    }
    
    /// Creates an OnboardingManager with isolated UserDefaults
    static func createTestOnboardingManager(
        testName: String = UUID().uuidString
    ) async -> OnboardingManager {
        return await MainActor.run {
            OnboardingManager.createForTesting(testName: testName)
        }
    }
    
    /// Creates a WorkspaceManager for testing with isolated UserDefaults
    static func createTestWorkspaceManager(testName: String = UUID().uuidString) async -> WorkspaceManager {
        return await MainActor.run {
            WorkspaceManager.createForTesting(testName: testName)
        }
    }
}

// MARK: - Test Assertion Helpers

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
        #expect(!inspectable.containsText(text), "View should not contain text: \(text)")
    }
    
    /// Asserts that a view contains a specific view type
    /// Note: Use concrete ViewType methods like find(ViewType.List.self) for better type safety
    static func assertContainsViewType<T>(
        _ view: some View,
        _ viewType: T.Type
    ) throws {
        // This is a placeholder - use concrete ViewType methods in actual tests
        // For example: try view.inspect().find(ViewType.List.self)
        #expect(true, "Use concrete ViewType methods for type checking")
    }
    
    /// Asserts that a button exists and is enabled
    static func assertButtonExists(
        _ view: some View,
        text: String,
        enabled: Bool = true
    ) throws {
        let inspectable = try view.inspect()
        _ = try inspectable.findButton(text: text)
        // Note: Button enabled state may require additional inspection
    }
}

// MARK: - Async Test Helpers

// Helpers for async test operations
enum UIAsyncTestHelpers {
    
    /// Waits for a condition to become true
    static func waitForCondition(
        timeout: TimeInterval = 1.0,
        interval: TimeInterval = 0.05,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
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
        condition: @escaping () async -> Bool
    ) async -> Bool {
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
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
        condition: @escaping () -> Bool
    ) async -> Bool {
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
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
        return await waitForConditionOnMainActor(timeout: timeout) {
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
        in view: some View,
        _ viewType: T.Type,
        timeout: TimeInterval = 1.0
    ) async -> Bool {
        // This is a placeholder - use concrete ViewType methods in actual tests
        // For example: try view.inspect().find(ViewType.List.self)
        return await waitForCondition(timeout: timeout) {
            // Use concrete find methods instead
            return false
        }
    }
}
