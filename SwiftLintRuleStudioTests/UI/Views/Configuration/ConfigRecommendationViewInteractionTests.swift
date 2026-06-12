//
//  ConfigRecommendationViewInteractionTests.swift
//  SwiftLintRuleStudioTests
//
//  Interaction tests for ConfigRecommendationView
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import SwiftUI
import Testing
import ViewInspector

/// Records the URL passed to an injected `OpenURLAction` so tests can assert
/// which URL a button would open without launching the real browser.
/// Touched only on the main actor inside the tests.
private final class OpenedURLRecorder: @unchecked Sendable {
    var capturedURL: URL?
}

// Interaction tests for ConfigRecommendationView
// SwiftUI views are implicitly @MainActor, but we'll use await MainActor.run { } inside tests
// to allow parallel test execution
@MainActor
struct ConfigRecommendationViewInteractionTests {

    // MARK: - Test Data Helpers

    private func createConfigRecommendationView() async -> (view: some View, workspaceManager: WorkspaceManager) {
        await MainActor.run {
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
        await UIAsyncTestHelpers.waitForConditionAsync(timeout: timeoutSeconds) {
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
        await UIAsyncTestHelpers.waitForText(
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

        // Inject an openURL override so the tap records the URL instead of
        // opening the real browser. ViewInspector types and `some View` aren't
        // Sendable, so the view is created, inspected, and tapped in one
        // MainActor.run block; only the Sendable recorder crosses the boundary.
        let recorder = OpenedURLRecorder()
        try await MainActor.run {
            let view = ConfigRecommendationView(workspaceManager: workspaceManager) { url in
                recorder.capturedURL = url
            }
            let button = try findButton(in: view, label: "Learn More")
            try button.tap()
        }

        #expect(
            recorder.capturedURL == URL(string: "https://github.com/realm/SwiftLint#configuration"),
            "Learn More button should open the SwiftLint configuration documentation"
        )
    }
}
