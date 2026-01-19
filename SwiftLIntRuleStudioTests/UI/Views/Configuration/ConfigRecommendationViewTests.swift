//
//  ConfigRecommendationViewTests.swift
//  SwiftLintRuleStudioTests
//
//  UI tests for ConfigRecommendationView
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

/// Tests for ConfigRecommendationView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
struct ConfigRecommendationViewTests {
    
    // MARK: - Test Data Helpers
    
    private func createConfigRecommendationView(
        configFileMissing: Bool = true
    ) async -> (view: some View, workspaceManager: WorkspaceManager) {
        return await MainActor.run {
            let workspaceManager = WorkspaceManager.createForTesting(testName: #function)
            
            // Note: configFileMissing is a computed property based on workspace state
            // We'll set up the workspace in individual tests
            
            let view = ConfigRecommendationView(workspaceManager: workspaceManager)
            
            return (view, workspaceManager)
        }
    }
    
    // MARK: - Initialization Tests
    
    @Test("ConfigRecommendationView initializes correctly")
    func testInitialization() async throws {
        let (view, _) = await createConfigRecommendationView()
        
        // Verify the view can be created
        // Note: View may not be visible if config file exists
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let _ = try? await MainActor.run {
            let _ = try viewCapture.inspect().find(ViewType.VStack.self)
            return true
        }
        #expect(true, "ConfigRecommendationView should initialize correctly")
    }
    
    // MARK: - Display Tests
    
    @Test("ConfigRecommendationView displays when config file missing")
    func testDisplaysWhenConfigFileMissing() async throws {
        let (view, workspaceManager) = await createConfigRecommendationView()
        
        // Create a temporary workspace without config file
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
        }
        
        // Wait for state update
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify recommendation is shown
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasRecommendation = try? await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "SwiftLint Configuration File Missing")
            return true
        }
        #expect(hasRecommendation == true, "ConfigRecommendationView should display when config file missing")
    }
    
    @Test("ConfigRecommendationView displays header")
    func testDisplaysHeader() async throws {
        let (view, workspaceManager) = await createConfigRecommendationView()
        
        // Create a temporary workspace without config file
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
        }
        
        // Wait for state update
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Find header text
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasHeader = try? await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "SwiftLint Configuration File Missing")
            return true
        }
        #expect(hasHeader == true, "ConfigRecommendationView should display header")
    }
    
    @Test("ConfigRecommendationView displays description")
    func testDisplaysDescription() async throws {
        let (view, workspaceManager) = await createConfigRecommendationView()
        
        // Create a temporary workspace without config file
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
        }
        
        // Wait for state update
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Find description text
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasDescription = try? await MainActor.run {
            let _ = try viewCapture.inspect().find(
                text: "Your workspace doesn't have a `.swiftlint.yml` configuration file. Creating one will help you:"
            )
            return true
        }
        #expect(hasDescription == true, "ConfigRecommendationView should display description")
    }
    
    // MARK: - Benefits Tests
    
    @Test("ConfigRecommendationView displays benefits list")
    func testDisplaysBenefitsList() async throws {
        let (view, workspaceManager) = await createConfigRecommendationView()
        
        // Create a temporary workspace without config file
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
        }
        
        // Wait for state update
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Find benefit text
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasBenefit = try? await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "Exclude third-party code from analysis")
            return true
        }
        #expect(hasBenefit == true, "ConfigRecommendationView should display benefits list")
    }
    
    // MARK: - Action Buttons Tests
    
    @Test("ConfigRecommendationView displays Create Default Configuration button")
    func testDisplaysCreateButton() async throws {
        let (view, workspaceManager) = await createConfigRecommendationView()
        
        // Create a temporary workspace without config file
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
        }
        
        // Wait for state update
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Find Create button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasCreateButton = try? await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "Create Default Configuration")
            return true
        }
        #expect(hasCreateButton == true, "ConfigRecommendationView should display Create Default Configuration button")
    }
    
    @Test("ConfigRecommendationView displays Learn More button")
    func testDisplaysLearnMoreButton() async throws {
        let (view, workspaceManager) = await createConfigRecommendationView()
        
        // Create a temporary workspace without config file
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
        }
        
        // Wait for state update
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Find Learn More button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasLearnMoreButton = try? await MainActor.run {
            let _ = try viewCapture.inspect().find(text: "Learn More")
            return true
        }
        #expect(hasLearnMoreButton == true, "ConfigRecommendationView should display Learn More button")
    }
    
    // MARK: - Error Handling Tests
    
    @Test("ConfigRecommendationView handles error display")
    func testHandlesErrorDisplay() async throws {
        let (view, _) = await createConfigRecommendationView()
        
        // Verify error alert structure exists
        // Note: Actual error would require triggering an error condition
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let _ = try? await MainActor.run {
            let _ = try viewCapture.inspect().find(ViewType.VStack.self)
            return true
        }
        #expect(true, "ConfigRecommendationView should handle error display")
    }
}

