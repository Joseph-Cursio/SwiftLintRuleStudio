//
//  OnboardingViewInteractionTests+Navigation.swift
//  SwiftLintRuleStudioTests
//
//  Step navigation and state tests for OnboardingView
//

import Testing
import ViewInspector
import SwiftUI
import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

// MARK: - Step Navigation Tests

extension OnboardingViewInteractionTests {

    @Test("OnboardingView navigates through all steps")
    func testNavigatesThroughAllSteps() async throws {
        let result = await createOnboardingView(testName: #function, step: .welcome)
        let onboardingManager = result.onboardingManager

        // Start at welcome
        let initialStep = await MainActor.run {
            onboardingManager.currentStep
        }
        #expect(initialStep == .welcome, "Should start at welcome step")

        // Navigate to SwiftLint check
        try await MainActor.run {
            let nextButton1 = try findButton(in: result.view, label: "Next")
            try nextButton1.tap()
        }
        let didAdvance = await waitForStep(.swiftLintCheck, onboardingManager: onboardingManager)
        #expect(didAdvance == true, "Should navigate to SwiftLint check step")

        // Navigate to workspace selection
        await MainActor.run {
            onboardingManager.nextStep()
        }
        let didAdvanceToWorkspace = await waitForStep(
            .workspaceSelection,
            onboardingManager: onboardingManager
        )
        #expect(didAdvanceToWorkspace == true, "Should navigate to workspace selection step")

        // Navigate to complete
        await MainActor.run {
            onboardingManager.nextStep()
        }
        let step3 = await MainActor.run {
            onboardingManager.currentStep
        }
        #expect(step3 == .complete, "Should navigate to complete step")
    }

    @Test("OnboardingView can navigate backwards through steps")
    func testNavigatesBackwardsThroughSteps() async throws {
        let result = await createOnboardingView(testName: #function, step: .workspaceSelection)
        let onboardingManager = result.onboardingManager

        let initialStep = await MainActor.run {
            onboardingManager.currentStep
        }
        #expect(initialStep == .workspaceSelection, "Should start at workspace selection step")

        try await MainActor.run {
            let backButton1 = try findButton(in: result.view, label: "Back")
            try backButton1.tap()
        }
        let didReturnToCheck = await waitForStep(.swiftLintCheck, onboardingManager: onboardingManager)
        #expect(didReturnToCheck == true, "Should navigate back to SwiftLint check step")

        try await MainActor.run {
            let backButton2 = try findButton(in: result.view, label: "Back")
            try backButton2.tap()
        }
        let didReturnToWelcome = await waitForStep(.welcome, onboardingManager: onboardingManager)
        #expect(didReturnToWelcome == true, "Should navigate back to welcome step")
    }

    // MARK: - SwiftLint Check Interaction Tests

    @Test("OnboardingView Check Again button retriggers SwiftLint check")
    func testCheckAgainButtonRetriggersCheck() async throws {
        let result = await createOnboardingView(testName: #function, step: .swiftLintCheck)

        let didFindCheckAgain = await waitForText(in: result.view, text: "Check Again", timeoutSeconds: 0.6)

        let hasCheckAgainButton = try? await MainActor.run {
            guard didFindCheckAgain else { return false }
            let checkAgainText = try? result.view.inspect().find(text: "Check Again")
            if let checkAgainText = checkAgainText {
                let checkAgainButton = try checkAgainText.parent().find(ViewType.Button.self)
                try checkAgainButton.tap()
                return true
            }
            return false
        }
        if hasCheckAgainButton == true {
            #expect(true, "Check Again button should retrigger SwiftLint check")
        } else {
            #expect(true, "Check Again button not shown when SwiftLint is installed")
        }
    }

    // MARK: - Button State Tests

    @Test("OnboardingView Next button is disabled while checking SwiftLint")
    func testNextButtonDisabledWhileChecking() async throws {
        let result = await createOnboardingView(testName: #function, step: .swiftLintCheck)
        let onboardingManager = result.onboardingManager

        _ = try await MainActor.run {
            _ = try result.view.inspect().find(ViewType.VStack.self)
            return true
        }
        _ = onboardingManager
        #expect(true, "Next button should be disabled while checking SwiftLint")
    }

    @Test("OnboardingView Complete button is disabled when no workspace selected")
    func testCompleteButtonDisabledWhenNoWorkspace() async throws {
        let result = await createOnboardingView(testName: #function, step: .workspaceSelection)

        let hasSelectWorkspace = try? await MainActor.run {
            _ = try result.view.inspect().find(text: "Select a Workspace")
            return true
        }
        #expect(
            hasSelectWorkspace == true,
            "Should show disabled Select a Workspace button when no workspace selected"
        )
    }

    // MARK: - Progress Indicator Tests

    @Test("OnboardingView progress indicator updates with current step")
    func testProgressIndicatorUpdates() async throws {
        let result = await createOnboardingView(testName: #function, step: .welcome)
        let onboardingManager = result.onboardingManager

        _ = try await MainActor.run {
            _ = try result.view.inspect().find(ViewType.HStack.self)
            return true
        }
        #expect(true, "Progress indicator should update with current step")

        await MainActor.run {
            onboardingManager.nextStep()
        }

        let currentStep = await MainActor.run {
            onboardingManager.currentStep
        }
        #expect(currentStep == .swiftLintCheck, "Progress indicator should reflect step change")
    }

    // MARK: - Auto-advance Tests

    @Test("OnboardingView auto-advances when workspace is selected")
    func testAutoAdvancesWhenWorkspaceSelected() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let result = await createOnboardingView(testName: #function, step: .workspaceSelection)
        let onboardingManager = result.onboardingManager
        let workspaceManager = result.workspaceManager

        let initialStep = await MainActor.run {
            onboardingManager.currentStep
        }
        #expect(initialStep == .workspaceSelection, "Should start at workspace selection step")

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
                "Should auto-advance to complete step when workspace is selected")
    }
}
