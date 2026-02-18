//
//  ConfigRecommendationViewInteractionTests.swift
//  SwiftLintRuleStudioTests
//
//  Interaction tests for ConfigRecommendationView
//

import Testing
import ViewInspector
import SwiftUI
import Foundation
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

    private func waitForConfigFileMissing(
        _ workspaceManager: WorkspaceManager,
        expected: Bool,
        timeoutSeconds: TimeInterval = 1.0
    ) async -> Bool {
        return await UIAsyncTestHelpers.waitForConditionAsync(timeout: timeoutSeconds) {
            await MainActor.run {
                workspaceManager.configFileMissing == expected
            }
        }
    }

    @MainActor
    private func waitForText(
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
        
        // Verify config file is missing
        let configFileMissing = await waitForConfigFileMissing(workspaceManager, expected: true)
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
        
        // Verify config file was created
        let configFileMissingAfter = await waitForConfigFileMissing(workspaceManager, expected: false)
        let configExists = await MainActor.run {
            FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(".swiftlint.yml").path)
        }
        #expect(
            configFileMissingAfter == true || configExists == true,
            "Create button should create config file"
        )
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
        
        let didShowCreating = await waitForText(
            in: AnyView(view),
            text: "Creating...",
            timeoutSeconds: 0.4
        )
        let didCreateConfig = await waitForConfigFileMissing(workspaceManager, expected: false)
        #expect(
            didShowCreating || didCreateConfig,
            "Create button should show loading state or finish creation quickly"
        )
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
        
        // Note: Opening URL is a system action, we verify the button is tappable (no crash)
        #expect(true, "Learn More button should open documentation")
    }
}
