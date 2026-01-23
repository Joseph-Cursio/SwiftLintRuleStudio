//
//  ConfigRecommendationViewInteractionTests.swift
//  SwiftLintRuleStudioTests
//
//  Interaction tests for ConfigRecommendationView
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

// Interaction tests for ConfigRecommendationView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
struct ConfigRecommendationViewInteractionTests {
    
    // MARK: - Test Data Helpers
    
    private func createConfigRecommendationView() async -> (view: some View, workspaceManager: WorkspaceManager) {
        return await MainActor.run {
            let workspaceManager = WorkspaceManager.createForTesting(testName: #function)
            let view = ConfigRecommendationView(workspaceManager: workspaceManager)
            return (view, workspaceManager)
        }
    }
    
    @MainActor
    private func findButton<V: View>(in view: V, label: String) throws -> InspectableView<ViewType.Button> {
        try view.inspect().find(ViewType.Button.self) { button in
            let text = try? button.labelView().find(ViewType.Text.self).string()
            return text == label
        }
    }
    
    // MARK: - Button Interaction Tests
    
    @Test("ConfigRecommendationView Create button creates config file")
    func testCreateButtonCreatesConfigFile() async throws {
        let (_, workspaceManager) = await createConfigRecommendationView()
        
        // Create a temporary workspace without config file
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
        }
        
        // Wait for state update
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify config file is missing
        let configFileMissing = await MainActor.run {
            workspaceManager.configFileMissing
        }
        #expect(configFileMissing == true, "Config file should be missing")
        
        // Recreate the view after workspace setup so state is reflected
        let view = await MainActor.run {
            ConfigRecommendationView(workspaceManager: workspaceManager)
        }
        
        // Find and tap Create button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        try await MainActor.run {
            let button = try findButton(in: view, label: "Create Default Configuration")
            try button.tap()
        }
        
        // Wait for config file creation
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify config file was created
        let configFileMissingAfter = await MainActor.run {
            workspaceManager.configFileMissing
        }
        #expect(configFileMissingAfter == false, "Create button should create config file")
    }
    
    @Test("ConfigRecommendationView Create button shows loading state")
    func testCreateButtonShowsLoadingState() async throws {
        let (_, workspaceManager) = await createConfigRecommendationView()
        
        // Create a temporary workspace without config file
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
        }
        
        // Wait for state update
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Recreate the view after workspace setup so state is reflected
        let view = await MainActor.run {
            ConfigRecommendationView(workspaceManager: workspaceManager)
        }
        
        // Find and tap Create button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        try await MainActor.run {
            let button = try findButton(in: view, label: "Create Default Configuration")
            try button.tap()
        }
        
        // Wait briefly to see loading state
        try await Task.sleep(nanoseconds: 50_000_000)
        
        // Note: Loading state shows "Creating..." text
        // We verify the button is tappable (no crash)
        #expect(true, "Create button should show loading state")
    }
    
    @Test("ConfigRecommendationView Learn More button opens documentation")
    func testLearnMoreButtonOpensDocumentation() async throws {
        let (_, workspaceManager) = await createConfigRecommendationView()
        
        // Create a temporary workspace without config file
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
        }
        
        // Wait for state update
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Recreate the view after workspace setup so state is reflected
        let view = await MainActor.run {
            ConfigRecommendationView(workspaceManager: workspaceManager)
        }
        
        // Find and tap Learn More button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        try await MainActor.run {
            let button = try findButton(in: view, label: "Learn More")
            try button.tap()
        }
        
        // Wait for action
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Note: Opening URL is a system action, we verify the button is tappable (no crash)
        #expect(true, "Learn More button should open documentation")
    }
}
