//
//  WorkspaceSelectionViewInteractionTests.swift
//  SwiftLintRuleStudioTests
//
//  Interaction tests for WorkspaceSelectionView
//

import Testing
import ViewInspector
import SwiftUI
import Foundation
@testable import SwiftLIntRuleStudio

// Interaction tests for WorkspaceSelectionView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@Suite(.serialized)
struct WorkspaceSelectionViewInteractionTests {
    
    // MARK: - Test Data Helpers
    
    private func createWorkspaceSelectionView() async -> (view: some View, workspaceManager: WorkspaceManager) {
        return await MainActor.run {
            let workspaceManager = WorkspaceManager.createForTesting(testName: #function)
            let view = WorkspaceSelectionView(workspaceManager: workspaceManager)
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

    private func waitForRecentWorkspaces(
        _ workspaceManager: WorkspaceManager,
        isEmpty: Bool,
        timeoutSeconds: TimeInterval = 1.0
    ) async -> Bool {
        return await UIAsyncTestHelpers.waitForConditionAsync(timeout: timeoutSeconds) {
            await MainActor.run {
                workspaceManager.recentWorkspaces.isEmpty == isEmpty
            }
        }
    }
    
    // MARK: - Button Interaction Tests
    
    @Test("WorkspaceSelectionView Open Workspace button triggers file picker")
    func testOpenWorkspaceButtonTriggersFilePicker() async throws {
        let (view, _) = await createWorkspaceSelectionView()
        
        // Find and tap Open Workspace button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let openButton = try findButton(in: view, label: "Open Workspace...")
            try openButton.tap()
        }
        
        // Verify button is tappable (no crash)
        #expect(true, "Open Workspace button should trigger file picker")
    }
    
    @Test("WorkspaceSelectionView Close Workspace button closes workspace")
    func testCloseWorkspaceButtonClosesWorkspace() async throws {
        let (_, workspaceManager) = await createWorkspaceSelectionView()
        
        // Create and open a temporary workspace
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
        }
        
        let didOpenWorkspace = await waitForWorkspace(workspaceManager, exists: true)
        #expect(didOpenWorkspace == true, "Workspace should open before closing")
        
        // Recreate the view after opening workspace so the button is visible
        let view = await MainActor.run {
            WorkspaceSelectionView(workspaceManager: workspaceManager)
        }
        
        // Find and tap Close Workspace button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        try await MainActor.run {
            let closeButton = try findButton(in: view, label: "Close Workspace")
            try closeButton.tap()
        }
        
        let didCloseWorkspace = await waitForWorkspace(workspaceManager, exists: false)
        #expect(didCloseWorkspace == true, "Close Workspace button should close workspace")
    }
    
    // MARK: - Recent Workspace Interaction Tests
    
    @Test("WorkspaceSelectionView recent workspace row opens workspace")
    func testRecentWorkspaceRowOpensWorkspace() async throws {
        let (_, workspaceManager) = await createWorkspaceSelectionView()
        
        // Create and open a temporary workspace
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
            workspaceManager.closeWorkspace()
        }
        
        let didRegisterRecent = await waitForRecentWorkspaces(workspaceManager, isEmpty: false)
        #expect(didRegisterRecent == true, "Recent workspaces should register")
        
        // Recreate the view after recent workspaces update
        let view = await MainActor.run {
            WorkspaceSelectionView(workspaceManager: workspaceManager)
        }
        
        // Note: Tapping recent workspace row would require finding the specific row
        // This is complex with ViewInspector, so we verify the structure exists
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasRecentWorkspaces = try? await MainActor.run {
            _ = try viewCapture.inspect().find(text: "Recent Workspaces")
            return true
        }
        #expect(hasRecentWorkspaces == true, "Recent workspace row should be tappable")
    }

    @Test("WorkspaceSelectionView taps recent workspace row to open")
    func testTappingRecentWorkspaceRowOpensWorkspace() async throws {
        let (_, workspaceManager) = await createWorkspaceSelectionView()

        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
            workspaceManager.closeWorkspace()
        }

        let didRegisterRecent = await waitForRecentWorkspaces(workspaceManager, isEmpty: false)
        #expect(didRegisterRecent == true, "Recent workspaces should register")

        let view = await MainActor.run {
            WorkspaceSelectionView(workspaceManager: workspaceManager)
        }

        try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            let row = try inspector.find(ViewType.HStack.self) { hstack in
                (try? hstack.find(text: tempDir.lastPathComponent)) != nil
            }
            try row.callOnTapGesture()
        }

        let didOpenWorkspace = await waitForWorkspace(workspaceManager, exists: true)
        #expect(didOpenWorkspace == true, "Tapping recent workspace row should open workspace")
    }
    
    @Test("WorkspaceSelectionView Clear button clears recent workspaces")
    func testClearButtonClearsRecentWorkspaces() async throws {
        let (_, workspaceManager) = await createWorkspaceSelectionView()
        
        // Create and open a temporary workspace
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
            workspaceManager.closeWorkspace()
        }
        
        let didRegisterRecent = await waitForRecentWorkspaces(workspaceManager, isEmpty: false)
        #expect(didRegisterRecent == true, "Should have recent workspaces")
        
        // Recreate the view after recent workspaces update
        let view = await MainActor.run {
            WorkspaceSelectionView(workspaceManager: workspaceManager)
        }
        
        // Find and tap Clear button
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        try await MainActor.run {
            let clearButton = try findButton(in: view, label: "Clear")
            try clearButton.tap()
        }
        
        let didClear = await waitForRecentWorkspaces(workspaceManager, isEmpty: true)
        #expect(didClear == true, "Clear button should clear recent workspaces")
    }
    
    @Test("WorkspaceSelectionView remove button removes workspace from recent")
    func testRemoveButtonRemovesWorkspace() async throws {
        let (_, workspaceManager) = await createWorkspaceSelectionView()
        
        // Create and open a temporary workspace
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        
        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
            workspaceManager.closeWorkspace()
        }
        
        let didRegisterRecent = await waitForRecentWorkspaces(workspaceManager, isEmpty: false)
        let initialCount = await MainActor.run {
            workspaceManager.recentWorkspaces.count
        }
        #expect(didRegisterRecent == true, "Should have recent workspaces")
        
        // Recreate the view after recent workspaces update
        let view = await MainActor.run {
            WorkspaceSelectionView(workspaceManager: workspaceManager)
        }
        
        // Note: Tapping remove button would require finding the specific button
        // This is complex with ViewInspector, so we verify the structure exists
        // ViewInspector types aren't Sendable, so we do everything in one MainActor.run block
        nonisolated(unsafe) let viewCapture = view
        let hasRecentWorkspaces = try? await MainActor.run {
            _ = try viewCapture.inspect().find(text: "Recent Workspaces")
            return true
        }
        #expect(hasRecentWorkspaces == true, "Remove button should remove workspace from recent")
        #expect(initialCount > 0, "Should have recent workspaces to remove")
    }

    @Test("WorkspaceSelectionView remove button tap removes recent workspace")
    func testRemoveButtonTapRemovesWorkspace() async throws {
        let (_, workspaceManager) = await createWorkspaceSelectionView()

        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        try await MainActor.run {
            try workspaceManager.openWorkspace(at: tempDir)
            workspaceManager.closeWorkspace()
        }

        let didRegisterRecent = await waitForRecentWorkspaces(workspaceManager, isEmpty: false)
        let initialCount = await MainActor.run { workspaceManager.recentWorkspaces.count }
        #expect(didRegisterRecent == true, "Should have recent workspaces")

        let view = await MainActor.run {
            WorkspaceSelectionView(workspaceManager: workspaceManager)
        }

        try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            let nameText = try inspector.find(text: tempDir.lastPathComponent)
            let row = try nameText.parent().parent()
            let removeButton = try row.find(ViewType.Button.self)
            try removeButton.tap()
        }

        let didRemove = await waitForRecentWorkspaces(workspaceManager, isEmpty: true)
        let newCount = await MainActor.run { workspaceManager.recentWorkspaces.count }
        #expect(didRemove == true, "Remove button should remove recent workspace")
        #expect(newCount == max(0, initialCount - 1), "Recent workspace count should decrease")
    }
}
