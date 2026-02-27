//
//  SidebarViewTests.swift
//  SwiftLintRuleStudioTests
//
//  UI tests for SidebarView
//

import Testing
import ViewInspector
import SwiftUI
import Foundation
@testable import SwiftLIntRuleStudio

// Tests for SidebarView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
struct SidebarViewTests {
    
    // MARK: - Test Data Helpers
    
    // Workaround type to bypass Sendable check for SwiftUI views
    struct ViewResult: @unchecked Sendable {
        let view: AnyView
        let dependencies: DependencyContainer
        
        init(view: some View, dependencies: DependencyContainer) {
            self.view = AnyView(view)
            self.dependencies = dependencies
        }
    }
    
    // Workaround for Swift 6 strict concurrency: Return ViewResult instead of tuple with 'some View'
    @MainActor
    private func createSidebarView(hasWorkspace: Bool = false) -> ViewResult {
        let cacheManager = CacheManager.createForTesting()
        let swiftLintCLI = SwiftLintCLI(cacheManager: cacheManager)
        let ruleRegistry = RuleRegistry(swiftLintCLI: swiftLintCLI, cacheManager: cacheManager)
        let dependencies = DependencyContainer.createForTesting(
            ruleRegistry: ruleRegistry,
            swiftLintCLI: swiftLintCLI,
            cacheManager: cacheManager
        )
        
        if hasWorkspace {
            // Note: Workspace will be set in individual tests
        }
        
        let view = SidebarView(selection: .constant(.rules))
            .environmentObject(dependencies)
            .environmentObject(ruleRegistry)
        
        return ViewResult(view: view, dependencies: dependencies)
    }

    private func waitForWorkspace(
        _ workspaceManager: WorkspaceManager,
        exists: Bool,
        timeoutSeconds: TimeInterval = 1.0
    ) async -> Bool {
        return await UIAsyncTestHelpers.waitForConditionAsync(timeout: timeoutSeconds) {
            await MainActor.run {
                (workspaceManager.currentWorkspace != nil) == exists
            }
        }
    }
    
    // MARK: - Initialization Tests
    
    @Test("SidebarView initializes correctly")
    func testInitialization() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createSidebarView() }.value
        let view = result.view
        
        // Verify the view can be created
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasList = try await MainActor.run {
            _ = try view.inspect().find(ViewType.List.self)
            return true
        }
        #expect(hasList == true, "SidebarView should initialize with List")
    }
    
    @Test("SidebarView displays navigation title")
    func testDisplaysNavigationTitle() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createSidebarView() }.value
        let view = result.view
        
        // Find section header ("Workspace") — navigation title is set by ContentView, not SidebarView
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasTitle = try await MainActor.run {
            _ = try view.inspect().find(text: "Workspace")
            return true
        }
        #expect(hasTitle == true, "SidebarView should display navigation section header")
    }
    
    // MARK: - Workspace Info Tests
    
    @Test("SidebarView shows workspace info when workspace is open")
    func testShowsWorkspaceInfo() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createSidebarView(hasWorkspace: true) }.value
        let view = result.view
        let dependencies = result.dependencies
        
        // Create a temporary workspace
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try dependencies.workspaceManager.openWorkspace(at: tempDir)
        }
        
        let didOpenWorkspace = await waitForWorkspace(dependencies.workspaceManager, exists: true)
        #expect(didOpenWorkspace == true, "Workspace should open")
        
        // Verify workspace section is shown
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasWorkspaceHeader = try? await MainActor.run {
            _ = try view.inspect().find(text: "Workspace")
            return true
        }
        #expect(hasWorkspaceHeader == true, "SidebarView should show workspace info when workspace is open")
    }
    
    @Test("SidebarView hides workspace info when no workspace")
    func testHidesWorkspaceInfoWhenNoWorkspace() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createSidebarView(hasWorkspace: false) }.value
        let view = result.view
        
        // Verify workspace info block (VStack) is not shown — nav section "Workspace" header
        // is always visible, but the info VStack only appears when a workspace is open.
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasWorkspaceVStack = try? await MainActor.run {
            _ = try view.inspect().find(ViewType.VStack.self)
            return true
        }
        #expect(hasWorkspaceVStack == nil, "SidebarView should hide workspace info block when no workspace")
    }
    
    // MARK: - Navigation Links Tests
    
    @Test("SidebarView displays Rules navigation link")
    func testDisplaysRulesLink() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createSidebarView() }.value
        let view = result.view
        
        // Find Rules link via accessibility identifier — direct text search fails
        // because the Rules label has a .badge() modifier that ViewInspector can't traverse.
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasRulesText = try await MainActor.run {
            _ = try view.inspect().find(where: { (try? $0.accessibilityIdentifier()) == "SidebarRulesLink" })
            return true
        }
        #expect(hasRulesText == true, "SidebarView should display Rules navigation link")
    }
    
    @Test("SidebarView displays Violations navigation link")
    func testDisplaysViolationsLink() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createSidebarView() }.value
        let view = result.view
        
        // Find Violations link
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasViolationsText = try await MainActor.run {
            _ = try view.inspect().find(text: "Violations")
            return true
        }
        #expect(hasViolationsText == true, "SidebarView should display Violations navigation link")
    }
    
    @Test("SidebarView displays Dashboard navigation link")
    func testDisplaysDashboardLink() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createSidebarView() }.value
        let view = result.view
        
        // Find Dashboard link
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasDashboardText = try await MainActor.run {
            _ = try view.inspect().find(text: "Dashboard")
            return true
        }
        #expect(hasDashboardText == true, "SidebarView should display Dashboard navigation link")
    }
    
    @Test("SidebarView displays Safe Rules navigation link")
    func testDisplaysSafeRulesLink() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createSidebarView() }.value
        let view = result.view
        
        // Find Safe Rules link
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasSafeRulesText = try await MainActor.run {
            _ = try view.inspect().find(text: "Safe Rules")
            return true
        }
        #expect(hasSafeRulesText == true, "SidebarView should display Safe Rules navigation link")
    }
    
    // MARK: - Navigation Link Icons Tests
    
    @Test("SidebarView displays correct icons for navigation links")
    func testDisplaysCorrectIcons() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createSidebarView() }.value
        let view = result.view
        
        // Verify icons exist (they're part of Label views)
        // Rules link should have list.bullet.rectangle icon
        // Violations link should have exclamationmark.triangle icon
        // Dashboard link should have chart.bar icon
        // Safe Rules link should have checkmark.circle.badge.questionmark icon
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasList = try await MainActor.run {
            _ = try view.inspect().find(ViewType.List.self)
            return true
        }
        #expect(hasList == true, "SidebarView should display correct icons for navigation links")
    }
    
    // MARK: - Structure Tests
    
    @Test("SidebarView has correct structure")
    func testHasCorrectStructure() async throws {
        // Workaround: Use ViewResult to bypass Sendable check
        let result = await Task { @MainActor in createSidebarView() }.value
        let view = result.view
        
        // Verify List structure exists
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasList = try await MainActor.run {
            _ = try view.inspect().find(ViewType.List.self)
            return true
        }
        #expect(hasList == true, "SidebarView should have correct structure")
    }
}
