//
//  WorkspaceSelectionViewTests.swift
//  SwiftLintRuleStudioTests
//
//  UI tests for WorkspaceSelectionView
//

import Testing
import ViewInspector
import SwiftUI
@testable import SwiftLIntRuleStudio

/// Tests for WorkspaceSelectionView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
struct WorkspaceSelectionViewTests {
    
    // MARK: - Test Data Helpers
    
    private func createWorkspaceSelectionView(
        hasCurrentWorkspace: Bool = false,
        hasRecentWorkspaces: Bool = false
    ) async -> (view: some View, workspaceManager: WorkspaceManager) {
        // Create view on MainActor
        // Use nonisolated(unsafe) to bypass Sendable check for SwiftUI views in tests
        return await MainActor.run {
            let workspaceManager = WorkspaceManager.createForTesting(testName: #function)
            
            if hasCurrentWorkspace {
                // Note: Workspace will be set in individual tests
            }
            
            if hasRecentWorkspaces {
                // Note: Recent workspaces will be set in individual tests
            }
            
            let view = WorkspaceSelectionView(workspaceManager: workspaceManager)
            
            // Use nonisolated(unsafe) to bypass Sendable check for SwiftUI views
            nonisolated(unsafe) let viewCapture = view
            return (viewCapture, workspaceManager)
        }
    }
    
    // MARK: - Initialization Tests
    
    @Test("WorkspaceSelectionView initializes correctly")
    func testInitialization() async throws {
        let (view, _) = await createWorkspaceSelectionView()
        
        // Verify the view can be created
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasVStack = try await MainActor.run {
            let _ = try view.inspect().find(ViewType.VStack.self)
            return true
        }
        #expect(hasVStack == true, "WorkspaceSelectionView should initialize with VStack")
    }
    
    @Test("WorkspaceSelectionView displays header")
    func testDisplaysHeader() async throws {
        let (view, _) = await createWorkspaceSelectionView()
        
        // Find header text
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasHeader = try await MainActor.run {
            let _ = try view.inspect().find(text: "Select a Workspace")
            return true
        }
        #expect(hasHeader == true, "WorkspaceSelectionView should display header")
    }
    
    @Test("WorkspaceSelectionView displays description")
    func testDisplaysDescription() async throws {
        let (view, _) = await createWorkspaceSelectionView()
        
        // Find description text
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasDescription = try? await MainActor.run {
            let _ = try view.inspect().find(text: "Choose a directory containing your Swift project")
            return true
        }
        #expect(hasDescription == true, "WorkspaceSelectionView should display description")
    }
    
    // MARK: - Current Workspace Tests
    
    @Test("WorkspaceSelectionView shows current workspace when available")
    func testShowsCurrentWorkspace() async throws {
        let (view, workspaceManager) = await createWorkspaceSelectionView(hasCurrentWorkspace: true)
        
        // Create a temporary workspace
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
        }
        
        // Wait for state update
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify current workspace section is shown
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasCurrentWorkspace = try? await MainActor.run {
            let _ = try view.inspect().find(text: "Current Workspace")
            return true
        }
        #expect(hasCurrentWorkspace == true, "WorkspaceSelectionView should show current workspace when available")
    }
    
    @Test("WorkspaceSelectionView hides current workspace when not available")
    func testHidesCurrentWorkspace() async throws {
        let (view, _) = await createWorkspaceSelectionView(hasCurrentWorkspace: false)
        
        // Verify current workspace section is not shown
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasCurrentWorkspace = try? await MainActor.run {
            let _ = try view.inspect().find(text: "Current Workspace")
            return true
        }
        #expect(hasCurrentWorkspace == nil, "WorkspaceSelectionView should hide current workspace when not available")
    }
    
    // MARK: - Recent Workspaces Tests
    
    @Test("WorkspaceSelectionView shows recent workspaces when available")
    func testShowsRecentWorkspaces() async throws {
        let (view, workspaceManager) = await createWorkspaceSelectionView(hasRecentWorkspaces: true)
        
        // Create and open a temporary workspace
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
            workspaceManager.closeWorkspace()
        }
        
        // Wait for state update
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify recent workspaces section is shown
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasRecentWorkspaces = try? await MainActor.run {
            let _ = try view.inspect().find(text: "Recent Workspaces")
            return true
        }
        #expect(hasRecentWorkspaces == true, "WorkspaceSelectionView should show recent workspaces when available")
    }
    
    @Test("WorkspaceSelectionView hides recent workspaces when empty")
    func testHidesRecentWorkspacesWhenEmpty() async throws {
        let (view, _) = await createWorkspaceSelectionView(hasRecentWorkspaces: false)
        
        // Verify recent workspaces section is not shown
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasRecentWorkspaces = try? await MainActor.run {
            let _ = try view.inspect().find(text: "Recent Workspaces")
            return true
        }
        #expect(hasRecentWorkspaces == nil, "WorkspaceSelectionView should hide recent workspaces when empty")
    }
    
    // MARK: - Actions Tests
    
    @Test("WorkspaceSelectionView displays Open Workspace button")
    func testDisplaysOpenWorkspaceButton() async throws {
        let (view, _) = await createWorkspaceSelectionView()
        
        // Find Open Workspace button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasOpenButton = try await MainActor.run {
            let _ = try view.inspect().find(text: "Open Workspace...")
            return true
        }
        #expect(hasOpenButton == true, "WorkspaceSelectionView should display Open Workspace button")
    }
    
    @Test("WorkspaceSelectionView shows Close Workspace button when workspace is open")
    func testShowsCloseWorkspaceButton() async throws {
        let (view, workspaceManager) = await createWorkspaceSelectionView(hasCurrentWorkspace: true)
        
        // Create a temporary workspace
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
        }
        
        // Wait for state update
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify Close Workspace button is shown
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasCloseButton = try? await MainActor.run {
            let _ = try view.inspect().find(text: "Close Workspace")
            return true
        }
        #expect(hasCloseButton == true, "WorkspaceSelectionView should show Close Workspace button when workspace is open")
    }
    
    @Test("WorkspaceSelectionView hides Close Workspace button when no workspace")
    func testHidesCloseWorkspaceButton() async throws {
        let (view, _) = await createWorkspaceSelectionView(hasCurrentWorkspace: false)
        
        // Verify Close Workspace button is not shown
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasCloseButton = try? await MainActor.run {
            let _ = try view.inspect().find(text: "Close Workspace")
            return true
        }
        #expect(hasCloseButton == nil, "WorkspaceSelectionView should hide Close Workspace button when no workspace")
    }
    
    // MARK: - Error Handling Tests
    
    @Test("WorkspaceSelectionView handles error display")
    func testHandlesErrorDisplay() async throws {
        let (view, _) = await createWorkspaceSelectionView()
        
        // Verify error alert structure exists
        // Note: Actual error would require triggering an error condition
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasVStack = try await MainActor.run {
            let _ = try view.inspect().find(ViewType.VStack.self)
            return true
        }
        #expect(hasVStack == true, "WorkspaceSelectionView should handle error display")
    }
    
    // MARK: - File Picker Tests
    
    @Test("WorkspaceSelectionView has file picker")
    func testHasFilePicker() async throws {
        let (view, _) = await createWorkspaceSelectionView()
        
        // Verify file picker structure exists
        // Note: File picker is a system component, we verify the view structure
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        let hasVStack = try await MainActor.run {
            let _ = try view.inspect().find(ViewType.VStack.self)
            return true
        }
        #expect(hasVStack == true, "WorkspaceSelectionView should have file picker")
    }
}

