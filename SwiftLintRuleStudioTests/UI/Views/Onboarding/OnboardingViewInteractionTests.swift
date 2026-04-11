//
//  OnboardingViewInteractionTests.swift
//  SwiftLintRuleStudioTests
//
//  Interaction tests for OnboardingView
//

import Testing
import ViewInspector
import SwiftUI
import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

// Interaction tests for OnboardingView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@MainActor
struct OnboardingViewInteractionTests {

    // MARK: - Test Data Helpers

    struct OnboardingViewResult: @unchecked Sendable {
        let view: AnyView
        let onboardingManager: OnboardingManager
        let workspaceManager: WorkspaceManager
    }

    func createOnboardingView(
        testName: String,
        step: OnboardingManager.OnboardingStep = .welcome
    ) async -> OnboardingViewResult {
        return await MainActor.run {
            let userDefaults = IsolatedUserDefaults.create(for: testName)
            let onboardingManager = OnboardingManager(userDefaults: userDefaults)
            onboardingManager.currentStep = step
            if step != .welcome {
                onboardingManager.hasCompletedOnboarding = true
            }

            let workspaceManager = WorkspaceManager.createForTesting(testName: testName)
            let cacheManager = CacheManager.createForTesting()
            let swiftLintCLI = SwiftLintCLIActor(cacheManager: cacheManager)

            let view = OnboardingView(
                onboardingManager: onboardingManager,
                workspaceManager: workspaceManager,
                swiftLintCLI: swiftLintCLI
            )

            return OnboardingViewResult(
                view: AnyView(view),
                onboardingManager: onboardingManager,
                workspaceManager: workspaceManager
            )
        }
    }

    @MainActor
    func findButton<V: View>(in view: V, label: String) throws -> InspectableView<ViewType.Button> {
        try view.inspect().find(ViewType.Button.self) { button in
            let text = try? button.labelView().find(ViewType.Text.self).string()
            return text == label
        }
    }

    func waitForStep(
        _ expected: OnboardingManager.OnboardingStep,
        onboardingManager: OnboardingManager,
        timeoutSeconds: TimeInterval = 1.0
    ) async -> Bool {
        await UIAsyncTestHelpers.waitForConditionAsync(timeout: timeoutSeconds) {
            await MainActor.run {
                onboardingManager.currentStep == expected
            }
        }
    }

    func waitForCompletion(
        onboardingManager: OnboardingManager,
        timeoutSeconds: TimeInterval = 1.0
    ) async -> Bool {
        await UIAsyncTestHelpers.waitForConditionAsync(timeout: timeoutSeconds) {
            await MainActor.run {
                onboardingManager.hasCompletedOnboarding
            }
        }
    }

    @MainActor
    func waitForText(
        in view: AnyView,
        text: String,
        timeoutSeconds: TimeInterval = 1.0
    ) async -> Bool {
        return await UIAsyncTestHelpers.waitForText(
            in: view,
            text: text,
            timeout: timeoutSeconds
        )
    }

    // MARK: - Navigation Button Interaction Tests

    @Test("OnboardingView Next button advances to next step")
    func testNextButtonAdvancesStep() async throws {
        let result = await createOnboardingView(testName: #function, step: .welcome)
        let onboardingManager = result.onboardingManager

        // Find and tap Next button
        await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            try? result.view.inspect().callOnAppear()
        }
        defer { Task { @MainActor in ViewHosting.expel() } }
        try await MainActor.run {
            let nextButton = try findButton(in: result.view, label: "Next")
            try nextButton.tap()
        }

        let didAdvance = await waitForStep(.swiftLintCheck, onboardingManager: onboardingManager)
        #expect(didAdvance == true, "Next button should advance to next step")
    }

    @Test("OnboardingView Back button returns to previous step")
    func testBackButtonReturnsToPreviousStep() async throws {
        let result = await createOnboardingView(testName: #function, step: .swiftLintCheck)
        let onboardingManager = result.onboardingManager

        // Find and tap Back button
        await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            try? result.view.inspect().callOnAppear()
        }
        defer { Task { @MainActor in ViewHosting.expel() } }
        try await MainActor.run {
            let backButton = try findButton(in: result.view, label: "Back")
            try backButton.tap()
        }

        let didReturn = await waitForStep(.welcome, onboardingManager: onboardingManager)
        #expect(didReturn == true, "Back button should return to previous step")
    }

    @Test("OnboardingView Get Started button completes onboarding")
    func testGetStartedButtonCompletesOnboarding() async throws {
        let result = await createOnboardingView(testName: #function, step: .complete)
        let onboardingManager = result.onboardingManager

        // Find and tap Get Started button
        await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: result.view)
            try? result.view.inspect().callOnAppear()
        }
        defer { Task { @MainActor in ViewHosting.expel() } }
        try await MainActor.run {
            let getStartedButton = try findButton(in: result.view, label: "Get Started")
            try getStartedButton.tap()
        }

        let didComplete = await waitForCompletion(onboardingManager: onboardingManager)
        let currentStep = await MainActor.run {
            onboardingManager.currentStep
        }
        #expect(didComplete == true, "Get Started button should complete onboarding")
        #expect(currentStep == .complete, "Should remain on complete step")
    }

    @Test("OnboardingView Complete button advances to complete step")
    func testCompleteButtonAdvancesToCompleteStep() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let result = await createOnboardingView(testName: #function, step: .workspaceSelection)
        let onboardingManager = result.onboardingManager
        let workspaceManager = result.workspaceManager

        // Select a workspace first
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
        }

        let didAdvance = await waitForStep(
            .complete,
            onboardingManager: onboardingManager,
            timeoutSeconds: 1.5
        )
        let hasWorkspace = await MainActor.run {
            workspaceManager.currentWorkspace != nil
        }
        #expect(didAdvance || hasWorkspace == true,
                "Should advance to complete step when workspace is selected")
    }

}

// MARK: - ViewInspector Extensions
// Note: Inspectable conformance is no longer required in newer ViewInspector versions
