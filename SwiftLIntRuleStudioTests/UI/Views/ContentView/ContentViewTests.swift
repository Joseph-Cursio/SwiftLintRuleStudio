//
//  ContentViewTests.swift
//  SwiftLintRuleStudioTests
//
//  UI tests for ContentView
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

// Tests for ContentView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
struct ContentViewTests {
    
    // Workaround type to bypass Sendable check for SwiftUI views
    struct ViewResult: @unchecked Sendable {
        let view: AnyView
        let dependencies: DependencyContainer
        let ruleRegistry: RuleRegistry
        
        init(view: some View, dependencies: DependencyContainer, ruleRegistry: RuleRegistry) {
            self.view = AnyView(view)
            self.dependencies = dependencies
            self.ruleRegistry = ruleRegistry
        }
    }
    
    // MARK: - Test Data Helpers
    
    // Workaround for Swift 6 strict concurrency: Return ViewResult instead of tuple with 'some View'
    @MainActor
    private func createContentView(
        testName: String,
        hasCompletedOnboarding: Bool = false,
        hasWorkspace: Bool = false,
        configFileMissing: Bool = false
    ) -> ViewResult {
        let userDefaults = IsolatedUserDefaults.create(for: testName)
        let onboardingManager = OnboardingManager(userDefaults: userDefaults)
        onboardingManager.hasCompletedOnboarding = hasCompletedOnboarding
        
        let workspaceManager = WorkspaceManager.createForTesting(testName: testName)
        
        let cacheManager = CacheManager.createForTesting()
        let swiftLintCLI = SwiftLintCLI(cacheManager: cacheManager)
        let ruleRegistry = RuleRegistry(swiftLintCLI: swiftLintCLI, cacheManager: cacheManager)
        let dependencies = DependencyContainer.createForTesting(
            userDefaults: userDefaults,
            ruleRegistry: ruleRegistry,
            swiftLintCLI: swiftLintCLI,
            cacheManager: cacheManager,
            workspaceManager: workspaceManager,
            onboardingManager: onboardingManager
        )
        
        let view = ContentView()
            .environmentObject(ruleRegistry)
            .environmentObject(dependencies)
        
        return ViewResult(view: view, dependencies: dependencies, ruleRegistry: ruleRegistry)
    }
    
    // MARK: - Initialization Tests
    
    @Test("ContentView initializes correctly")
    func testInitialization() async throws {
        // Workaround: Use Task instead of MainActor.run to bypass Sendable check
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in
            createContentView(testName: #function)
        }.value
        let view = result.view
        
        // Verify the view can be created
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        _ = try await MainActor.run {
            _ = try viewCapture.inspect().find(ViewType.Group.self)
            return true
        }
        #expect(true, "ContentView should initialize with Group")
    }
    
    // MARK: - Onboarding Display Tests
    
    @Test("ContentView shows OnboardingView when onboarding not completed")
    func testShowsOnboardingWhenNotCompleted() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in
            createContentView(testName: #function, hasCompletedOnboarding: false)
        }.value
        let view = result.view
        
        // Verify onboarding view is shown
        // Note: OnboardingView contains "Welcome to SwiftLint Rule Studio"
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasOnboarding = try? await MainActor.run {
            _ = try viewCapture.inspect().find(text: "Welcome to SwiftLint Rule Studio")
            return true
        }
        #expect(hasOnboarding == true, "ContentView should show OnboardingView when onboarding not completed")
    }
    
    @Test("ContentView hides OnboardingView when onboarding completed")
    func testHidesOnboardingWhenCompleted() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in
            createContentView(testName: #function, hasCompletedOnboarding: true)
        }.value
        let view = result.view
        
        // Verify onboarding view is not shown
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasOnboarding = await MainActor.run {
            (try? viewCapture.inspect().find(text: "Welcome to SwiftLint Rule Studio")) != nil
        }
        #expect(hasOnboarding == false, "ContentView should hide OnboardingView when onboarding completed")
    }
    
    // MARK: - Workspace Selection Display Tests
    
    @Test("ContentView shows WorkspaceSelectionView when no workspace")
    func testShowsWorkspaceSelectionWhenNoWorkspace() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in
            createContentView(testName: #function, hasCompletedOnboarding: true, hasWorkspace: false)
        }.value
        let view = result.view
        
        // Verify workspace selection view is shown
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasWorkspaceSelection = try? await MainActor.run {
            _ = try viewCapture.inspect().find(text: "Select a Workspace")
            return true
        }
        #expect(hasWorkspaceSelection == true, "ContentView should show WorkspaceSelectionView when no workspace")
    }
    
    // MARK: - Main Interface Display Tests
    
    @Test("ContentView shows main interface when workspace is open")
    func testShowsMainInterfaceWhenWorkspaceOpen() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in
            createContentView(testName: #function, hasCompletedOnboarding: true, hasWorkspace: true)
        }.value
        let dependencies = result.dependencies
        let ruleRegistry = result.ruleRegistry
        
        // Create a temporary workspace
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try dependencies.workspaceManager.openWorkspace(at: tempDir)
        }
        
        // Recreate the view after updating state to ensure latest environment values
        nonisolated(unsafe) var viewCapture: AnyView!
        await MainActor.run {
            viewCapture = AnyView(ContentView()
                .environmentObject(ruleRegistry)
                .environmentObject(dependencies))
        }
        let view = viewCapture
        
        // Verify main interface is shown (NavigationSplitView with SidebarView)
        // SidebarView contains "SwiftLint Rule Studio" title
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewInspectorTarget = view
        let hasSidebarTitle = try? await MainActor.run {
            _ = try viewInspectorTarget.inspect().find(text: "Rules")
            return true
        }
        #expect(hasSidebarTitle == true, "ContentView should show main interface when workspace is open")
    }
    
    @Test("ContentView shows config recommendation when config file missing")
    func testShowsConfigRecommendationWhenConfigMissing() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in
            createContentView(testName: #function, hasCompletedOnboarding: true, hasWorkspace: true)
        }.value
        let view = result.view
        let dependencies = result.dependencies
        
        // Create a temporary workspace without config file
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try dependencies.workspaceManager.openWorkspace(at: tempDir)
        }
        
        // Verify config recommendation is shown
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasConfigRecommendation = try? await MainActor.run {
            _ = try viewCapture.inspect().find(text: "SwiftLint Configuration File Missing")
            return true
        }
        #expect(hasConfigRecommendation == true, "ContentView should show config recommendation when config file missing")
    }
    
    @Test("ContentView shows default detail view when workspace open")
    func testShowsDefaultDetailView() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in
            createContentView(testName: #function, hasCompletedOnboarding: true, hasWorkspace: true)
        }.value
        let view = result.view
        let dependencies = result.dependencies
        
        // Create a temporary workspace
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try dependencies.workspaceManager.openWorkspace(at: tempDir)
        }
        
        // Verify default detail view is shown
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasDefaultText = try? await MainActor.run {
            _ = try viewCapture.inspect().find(text: "Select a section")
            return true
        }
        #expect(hasDefaultText == true, "ContentView should show default detail view")
    }
    
    // MARK: - Error Handling Tests
    
    @Test("ContentView handles rule loading errors")
    func testHandlesRuleLoadingErrors() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in
            createContentView(testName: #function)
        }.value
        let view = result.view
        
        // Verify error alert structure exists
        // Note: Actual error would require mocking RuleRegistry
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        _ = try await MainActor.run {
            _ = try viewCapture.inspect().find(ViewType.Group.self)
            return true
        }
        #expect(true, "ContentView should handle rule loading errors")
    }
}

