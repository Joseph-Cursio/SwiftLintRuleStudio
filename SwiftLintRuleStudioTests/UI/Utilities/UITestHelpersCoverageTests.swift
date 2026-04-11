//
//  UITestHelpersCoverageTests.swift
//  SwiftLintRuleStudioTests
//
//  Coverage-focused tests for UI test helpers and extensions
//

import Testing
import SwiftUI
import ViewInspector
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

@MainActor
struct UITestHelpersCoverageTests {

    @Test("UITestDataFactory creates rules and violations")
    // swiftlint:disable:next function_body_length
    func testDataFactoryRulesAndViolations() async throws {
        let rule = UITestDataFactory.createTestRule(
            id: "rule_id",
            name: "Rule Name",
            description: "Rule description",
            category: .style,
            isOptIn: true,
            isEnabled: true,
            severity: .warning,
            supportsAutocorrection: true,
            minimumSwiftVersion: "5.9",
            defaultSeverity: .error,
            markdownDocumentation: "Docs"
        )

        let ruleValues = await MainActor.run {
            (
                rule.id,
                rule.name,
                rule.category,
                rule.isOptIn,
                rule.isEnabled,
                rule.severity,
                rule.supportsAutocorrection,
                rule.minimumSwiftVersion,
                rule.defaultSeverity,
                rule.markdownDocumentation
            )
        }
        #expect(ruleValues.0 == "rule_id")
        #expect(ruleValues.1 == "Rule Name")
        #expect(ruleValues.2 == .style)
        #expect(ruleValues.3)
        #expect(ruleValues.4)
        #expect(ruleValues.5 == .warning)
        #expect(ruleValues.6)
        #expect(ruleValues.7 == "5.9")
        #expect(ruleValues.8 == .error)
        #expect(ruleValues.9 == "Docs")

        let rules = await UITestDataFactory.createTestRules(count: 3, prefix: "rule")
        let ruleCategories = await MainActor.run {
            (rules.count, rules[0].category, rules[1].category)
        }
        #expect(ruleCategories.0 == 3)
        #expect(ruleCategories.1 == .lint)
        #expect(ruleCategories.2 == .style)

        let violation = UITestDataFactory.createTestViolation(
            ruleID: "rule_id",
            filePath: "File.swift",
            line: 42,
            severity: .error,
            suppressed: true,
            suppressionReason: "Testing"
        )

        let violationValues = await MainActor.run {
            (
                violation.ruleID,
                violation.filePath,
                violation.line,
                violation.severity,
                violation.suppressed,
                violation.suppressionReason
            )
        }
        #expect(violationValues.0 == "rule_id")
        #expect(violationValues.1 == "File.swift")
        #expect(violationValues.2 == 42)
        #expect(violationValues.3 == .error)
        #expect(violationValues.4)
        #expect(violationValues.5 == "Testing")

        let violations = await UITestDataFactory.createTestViolations(count: 2)
        let violationCount = await MainActor.run { violations.count }
        #expect(violationCount == 2)
    }

    @Test("UITestDataFactory creates workspaces")
    func testWorkspaceFactory() async throws {
        let workspace = UITestDataFactory.createTestWorkspace(name: "Workspace")
        let workspaceValues = await MainActor.run {
            (workspace.name, workspace.path.path.isEmpty)
        }
        #expect(workspaceValues.0 == "Workspace")
        #expect(workspaceValues.1 == false)
    }

    @Test("UIViewTestHelpers create dependency containers and views")
    func testViewHelpers() async throws {
        let container = await UIViewTestHelpers.createTestDependencyContainer()
        let isRecentWorkspacesEmpty = await MainActor.run {
            container.workspaceManager.recentWorkspaces.isEmpty
        }
        #expect(isRecentWorkspacesEmpty)

        let view = Text("Hello")
        let hasHelloText = await MainActor.run {
            let wrappedView = UIViewTestHelpers.createViewWithDependencies(view, dependencyContainer: container)
            ViewHosting.expel()
            ViewHosting.host(view: wrappedView)
            defer { ViewHosting.expel() }
            return (try? wrappedView.inspect().find(text: "Hello")) != nil
        }
        #expect(hasHelloText)

        let hasFullText = await MainActor.run {
            let fullView = UIViewTestHelpers.createViewWithFullDependencies(Text("Full"))
            ViewHosting.expel()
            ViewHosting.host(view: fullView)
            defer { ViewHosting.expel() }
            return (try? fullView.inspect().find(text: "Full")) != nil
        }
        #expect(hasFullText)
    }

    @Test("UIViewTestHelpers create managers for testing")
    func testManagerHelpers() async throws {
        let onboardingManager = await UIViewTestHelpers.createTestOnboardingManager(testName: #function)
        let onboardingValues = await MainActor.run {
            (onboardingManager.currentStep, onboardingManager.hasCompletedOnboarding)
        }
        #expect(onboardingValues.0 == .welcome)
        #expect(onboardingValues.1 == false)

        let workspaceManager = await UIViewTestHelpers.createTestWorkspaceManager(testName: #function)
        let workspaceValues = await MainActor.run {
            (workspaceManager.currentWorkspace == nil, workspaceManager.recentWorkspaces.isEmpty)
        }
        #expect(workspaceValues.0)
        #expect(workspaceValues.1)
    }

    @Test("UITestAssertions validate common view expectations")
    func testAssertionsHelpers() async throws {
        try await MainActor.run {
            let textView = Text("Hello")
            try UITestAssertions.assertContainsText(textView, text: "Hello")
            try UITestAssertions.assertNotContainsText(textView, text: "Missing")
            try UITestAssertions.assertContainsViewType(textView, ViewType.Text.self)

            let buttonView = VStack {
                Text("Tap Me")
                Button("Tap Me") {}
            }
            try UITestAssertions.assertButtonExists(buttonView, text: "Tap Me")
        }
    }

    @Test("UIAsyncTestHelpers wait for conditions and text")
    func testAsyncHelpers() async throws {
        let conditionTrue = await UIAsyncTestHelpers.waitForCondition(timeout: 0.2) {
            true
        }
        #expect(conditionTrue)

        let conditionFalse = await UIAsyncTestHelpers.waitForCondition(timeout: 0.05) {
            false
        }
        #expect(conditionFalse == false)

        let textFound = await Task { @MainActor in
            let view = Text("Async Text")
            return await UIAsyncTestHelpers.waitForText(in: view, text: "Async Text", timeout: 0.2)
        }.value
        #expect(textFound)

        let viewTypeFound = await Task { @MainActor in
            let view = Text("Async Text")
            return await UIAsyncTestHelpers.waitForViewType(in: view, ViewType.Text.self, timeout: 0.05)
        }.value
        #expect(viewTypeFound == false)
    }

}
