//
//  OnboardingViewAdditionalTests.swift
//  SwiftLintRuleStudioTests
//
//  Additional tests for OnboardingView (split from OnboardingViewTests)
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

@Suite(.serialized)
@MainActor
struct OnboardingViewAdditionalTests {

    // MARK: - Test Data Helpers

    private struct OnboardingViewResult: @unchecked Sendable {
        let view: AnyView
        let onboardingManager: OnboardingManager
        let workspaceManager: WorkspaceManager
    }

    private func createOnboardingView(
        testName: String,
        step: OnboardingManager.OnboardingStep = .welcome,
        swiftLintStatus: OnboardingView.SwiftLintStatus = .checking
    ) async -> OnboardingViewResult {
        return await MainActor.run {
            let userDefaults = IsolatedUserDefaults.create(for: testName)
            let onboardingManager = OnboardingManager(userDefaults: userDefaults)
            onboardingManager.currentStep = step

            let workspaceManager = WorkspaceManager.createForTesting(testName: testName)
            let cacheManager = CacheManager.createForTesting()
            let swiftLintCLI = SwiftLintCLIActor(cacheManager: cacheManager)

            let view = OnboardingView(
                onboardingManager: onboardingManager,
                workspaceManager: workspaceManager,
                swiftLintCLI: swiftLintCLI,
                swiftLintStatus: swiftLintStatus
            )

            return OnboardingViewResult(
                view: AnyView(view),
                onboardingManager: onboardingManager,
                workspaceManager: workspaceManager
            )
        }
    }

    // MARK: - Complete Step Tests

    @Test("OnboardingView displays complete step")
    func testDisplaysCompleteStep() async throws {
        let view = (await createOnboardingView(testName: #function, step: .complete)).view

        let hasComplete = try await MainActor.run {
            _ = try view.inspect().find(text: "You're All Set!")
            return true
        }
        #expect(hasComplete == true, "OnboardingView should display complete step")
    }

    @Test("OnboardingView complete step shows completion message")
    func testCompleteStepShowsMessage() async throws {
        let view = (await createOnboardingView(testName: #function, step: .complete)).view

        let completionMessage = "SwiftLint Rule Studio is ready to use. " +
            "Start by browsing rules or inspecting violations in your workspace."
        let hasMessage = try? await MainActor.run {
            _ = try view.inspect().find(text: completionMessage)
            return true
        }
        #expect(hasMessage == true, "Complete step should show completion message")
    }

    // MARK: - Navigation Buttons Tests

    @Test("OnboardingView shows Next button on welcome step")
    func testShowsNextButtonOnWelcome() async throws {
        let view = (await createOnboardingView(testName: #function, step: .welcome)).view

        let hasNext = try await MainActor.run {
            _ = try view.inspect().find(text: "Next")
            return true
        }
        #expect(hasNext == true, "OnboardingView should show Next button on welcome step")
    }

    @Test("OnboardingView shows Back button when not on welcome step")
    func testShowsBackButton() async throws {
        let view = (await createOnboardingView(testName: #function, step: .swiftLintCheck)).view

        let hasBack = try await MainActor.run {
            _ = try view.inspect().find(text: "Back")
            return true
        }
        #expect(hasBack == true, "OnboardingView should show Back button when not on welcome step")
    }

    @Test("OnboardingView hides Back button on welcome step")
    func testHidesBackButtonOnWelcome() async throws {
        let view = (await createOnboardingView(testName: #function, step: .welcome)).view

        let hasBack = await MainActor.run {
            (try? view.inspect().find(text: "Back")) != nil
        }
        #expect(hasBack == false, "OnboardingView should hide Back button on welcome step")
    }

    @Test("OnboardingView shows Complete button on workspace selection when workspace selected")
    func testShowsCompleteButtonWhenWorkspaceSelected() async throws {
        let result = await createOnboardingView(testName: #function, step: .workspaceSelection)
        let view = result.view
        let workspaceManager = result.workspaceManager

        _ = try await MainActor.run {
            _ = try view.inspect().find(ViewType.VStack.self)
            return true
        }
        _ = workspaceManager
        #expect(true, "OnboardingView should show Complete button when workspace is selected")
    }

    @Test("OnboardingView shows Get Started button on complete step")
    func testShowsGetStartedButton() async throws {
        let view = (await createOnboardingView(testName: #function, step: .complete)).view

        let hasGetStarted = try await MainActor.run {
            _ = try view.inspect().find(text: "Get Started")
            return true
        }
        #expect(hasGetStarted == true, "OnboardingView should show Get Started button on complete step")
    }

    @Test("OnboardingView shows disabled workspace prompt when none selected")
    func testWorkspaceSelectionShowsDisabledPrompt() async throws {
        let view = (await createOnboardingView(testName: #function, step: .workspaceSelection)).view

        let hasPrompt = try await MainActor.run {
            _ = try view.inspect().find(text: "Select a Workspace")
            _ = try view.inspect().find(text: "Choose a directory to continue")
            return true
        }
        #expect(hasPrompt == true, "Workspace selection should show disabled prompt when no workspace")
    }

    @Test("OnboardingView Complete button advances to complete step")
    func testCompleteButtonAdvancesStep() async throws {
        let result = await createOnboardingView(testName: #function, step: .workspaceSelection)
        let view = result.view
        let onboardingManager = result.onboardingManager
        let workspaceManager = result.workspaceManager

        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
        }

        try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            onboardingManager.currentStep = .workspaceSelection
            let inspector = try view.inspect()
            let button = try inspector.find(ViewType.Button.self) { button in
                (try? button.labelView().text().string()) == "Complete"
            }
            try button.tap()
        }

        let currentStep = await MainActor.run { onboardingManager.currentStep }
        #expect(currentStep == .complete, "Complete button should advance onboarding step")
    }

    @Test("OnboardingView Get Started button completes onboarding")
    func testGetStartedCompletesOnboarding() async throws {
        let result = await createOnboardingView(testName: #function, step: .complete)
        let view = result.view
        let onboardingManager = result.onboardingManager

        try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            onboardingManager.currentStep = .complete
            let inspector = try view.inspect()
            let button = try inspector.find(ViewType.Button.self) { button in
                (try? button.labelView().text().string()) == "Get Started"
            }
            try button.tap()
        }

        let didComplete = await MainActor.run { onboardingManager.hasCompletedOnboarding }
        #expect(didComplete == true, "Get Started should complete onboarding")
    }

    // MARK: - Step Transition Tests

    @Test("OnboardingView transitions between steps")
    func testTransitionsBetweenSteps() async throws {
        let result = await createOnboardingView(testName: #function, step: .welcome)
        let view = result.view
        let onboardingManager = result.onboardingManager

        let hasWelcome = try await MainActor.run {
            _ = try view.inspect().find(text: "Welcome to SwiftLint Rule Studio")
            return true
        }
        #expect(hasWelcome == true, "Should start at welcome step")

        await MainActor.run {
            onboardingManager.nextStep()
        }

        let currentStep = await MainActor.run {
            onboardingManager.currentStep
        }
        #expect(currentStep == .swiftLintCheck, "Should transition to SwiftLint check step")
    }
}
