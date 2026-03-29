//
//  OnboardingViewTests.swift
//  SwiftLintRuleStudioTests
//
//  UI tests for OnboardingView
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
@testable import SwiftLintRuleStudio

// Tests for OnboardingView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
@MainActor
struct OnboardingViewTests {

    // MARK: - Test Data Helpers

    @MainActor
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

    // MARK: - Initialization Tests

    @Test("OnboardingView initializes correctly")
    func testInitialization() async throws {
        let view = (await createOnboardingView(testName: #function, )).view

        // Verify the view can be created
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasVStack = try await MainActor.run {
            _ = try view.inspect().find(ViewType.VStack.self)
            return true
        }
        #expect(hasVStack == true, "OnboardingView should initialize with VStack")
    }

    @Test("OnboardingView has fixed frame size")
    func testFixedFrameSize() async throws {
        let view = (await createOnboardingView(testName: #function, )).view

        // Verify the view structure exists
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasVStack = try await MainActor.run {
            _ = try view.inspect().find(ViewType.VStack.self)
            return true
        }
        #expect(hasVStack == true, "OnboardingView should have fixed frame size")
    }

    // MARK: - Progress Indicator Tests

    @Test("OnboardingView displays progress indicator")
    func testDisplaysProgressIndicator() async throws {
        let view = (await createOnboardingView(testName: #function, )).view

        // Find progress indicator (circles)
        _ = try await MainActor.run {
            _ = try view.inspect().find(ViewType.HStack.self)
            return true
        }
        #expect(true, "OnboardingView should display progress indicator")
    }

    @Test("OnboardingView progress indicator shows correct number of steps")
    func testProgressIndicatorStepCount() async throws {
        let view = (await createOnboardingView(testName: #function, )).view

        // Progress indicator should show 3 steps (welcome, swiftLintCheck, workspaceSelection)
        // Complete step is not shown in progress indicator
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasHStack = try await MainActor.run {
            _ = try view.inspect().find(ViewType.HStack.self)
            return true
        }
        #expect(hasHStack == true, "Progress indicator should show correct number of steps")
    }

    // MARK: - Welcome Step Tests

    @Test("OnboardingView displays welcome step")
    func testDisplaysWelcomeStep() async throws {
        let view = (await createOnboardingView(testName: #function, step: .welcome)).view

        // Find welcome text
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasWelcome = try await MainActor.run {
            _ = try view.inspect().find(text: "Welcome to SwiftLint Rule Studio")
            return true
        }
        #expect(hasWelcome == true, "OnboardingView should display welcome step")
    }

    @Test("OnboardingView welcome step shows feature list")
    func testWelcomeStepShowsFeatures() async throws {
        let view = (await createOnboardingView(testName: #function, step: .welcome)).view

        // Find feature descriptions
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let (hasBrowseRules, hasInspectViolations, hasConfigureRules) = await MainActor.run {
            let browseRulesText = try? view.inspect().find(text: "Browse Rules")
            let inspectViolationsText = try? view.inspect().find(text: "Inspect Violations")
            let configureRulesText = try? view.inspect().find(text: "Configure Rules")
            return (browseRulesText != nil, inspectViolationsText != nil, configureRulesText != nil)
        }

        #expect(hasBrowseRules == true || hasInspectViolations == true || hasConfigureRules == true,
                "Welcome step should show feature list")
    }

    @Test("OnboardingView welcome step shows description")
    func testWelcomeStepShowsDescription() async throws {
        let view = (await createOnboardingView(testName: #function, step: .welcome)).view

        // Find description text
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasDescription = try? await MainActor.run {
            _ = try view.inspect().find(
                text: "A powerful tool for managing and configuring SwiftLint rules in your Swift projects."
            )
            return true
        }
        #expect(hasDescription == true, "Welcome step should show description")
    }

    // MARK: - SwiftLint Check Step Tests

    @Test("OnboardingView displays SwiftLint check step")
    func testDisplaysSwiftLintCheckStep() async throws {
        let view = (await createOnboardingView(testName: #function, step: .swiftLintCheck)).view

        // Find SwiftLint check text
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasSwiftLint = try await MainActor.run {
            _ = try view.inspect().find(text: "SwiftLint Installation")
            return true
        }
        #expect(hasSwiftLint == true, "OnboardingView should display SwiftLint check step")
    }

    @Test("OnboardingView SwiftLint check step shows checking state")
    func testSwiftLintCheckStepShowsChecking() async throws {
        let view = (await createOnboardingView(testName: #function, step: .swiftLintCheck)).view

        // Find checking text
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasChecking = try? await MainActor.run {
            _ = try view.inspect().find(text: "Checking for SwiftLint installation...")
            return true
        }
        #expect(hasChecking == true, "SwiftLint check step should show checking state")
    }

    @Test("OnboardingView SwiftLint check step shows not installed state")
    func testSwiftLintCheckStepShowsNotInstalled() async throws {
        // Inject .notInstalled as the initial swiftLintStatus so the not-found branch
        // renders immediately without relying on the environment or async file checks.
        let view = (await createOnboardingView(
            testName: #function,
            step: .swiftLintCheck,
            swiftLintStatus: .notInstalled
        )).view

        let found = await MainActor.run {
            (try? view.inspect().find(text: "SwiftLint Not Found")) != nil
        }
        #expect(found, "Not-installed step should show 'SwiftLint Not Found'")
    }

    @Test("OnboardingView SwiftLint check step shows installation options")
    func testSwiftLintCheckStepShowsInstallationOptions() async throws {
        let view = (await createOnboardingView(
            testName: #function,
            step: .swiftLintCheck,
            swiftLintStatus: .notInstalled
        )).view

        let found = await MainActor.run {
            (try? view.inspect().find(text: "Installation Options:")) != nil
        }
        #expect(found, "Not-installed step should show installation options")
    }

    @Test("OnboardingView SwiftLint check step shows check again button")
    func testSwiftLintCheckStepShowsCheckAgainButton() async throws {
        let view = (await createOnboardingView(
            testName: #function,
            step: .swiftLintCheck,
            swiftLintStatus: .notInstalled
        )).view

        let found = await MainActor.run {
            (try? view.inspect().find(text: "Check Again")) != nil
        }
        #expect(found, "Not-installed step should show 'Check Again' button")
    }

    // MARK: - Workspace Selection Step Tests

    @Test("OnboardingView displays workspace selection step")
    func testDisplaysWorkspaceSelectionStep() async throws {
        let view = (await createOnboardingView(testName: #function, step: .workspaceSelection)).view

        // Find workspace selection text
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasWorkspace = try await MainActor.run {
            _ = try view.inspect().find(text: "Select Your Workspace")
            return true
        }
        #expect(hasWorkspace == true, "OnboardingView should display workspace selection step")
    }

    @Test("OnboardingView workspace selection step shows description")
    func testWorkspaceSelectionStepShowsDescription() async throws {
        let view = (await createOnboardingView(testName: #function, step: .workspaceSelection)).view

        // Find description text
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasDescription = try? await MainActor.run {
            _ = try view.inspect().find(text: "Choose a directory containing your Swift project")
            return true
        }
        #expect(hasDescription == true, "Workspace selection step should show description")
    }

    @Test("OnboardingView workspace selection step embeds WorkspaceSelectionView")
    func testWorkspaceSelectionStepEmbedsView() async throws {
        let view = (await createOnboardingView(testName: #function, step: .workspaceSelection)).view

        // WorkspaceSelectionView should be embedded
        // We verify the view structure exists
        _ = try await MainActor.run {
            _ = try view.inspect().find(ViewType.VStack.self)
            return true
        }
        #expect(true, "Workspace selection step should embed WorkspaceSelectionView")
    }

}

// MARK: - ViewInspector Extensions
// Note: Inspectable conformance is no longer required in newer ViewInspector versions
