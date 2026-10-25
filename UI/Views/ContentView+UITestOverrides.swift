//
//  ContentView+UITestOverrides.swift
//  SwiftLintRuleStudio
//
//  UI-test bootstrap helpers that read process args/env to skip the
//  onboarding flow and seed a temporary workspace before the main view
//  renders. Kept separate so the production ContentView body stays
//  focused on real-user state.
//

import Foundation
import SwiftLintRuleStudioCore

extension ContentView {
    func applyUITestOverrides() {
        let processInfo = ProcessInfo.processInfo
        guard processInfo.arguments.contains("-uiTesting") else { return }

        let environment = processInfo.environment
        if environment["UI_TEST_SKIP_ONBOARDING"] == "1" {
            dependencies.onboardingManager.completeOnboarding()
        }

        if environment["UI_TEST_WORKSPACE"] == "1" {
            if let workspaceURL = try? createUITestWorkspace() {
                try? dependencies.workspaceManager.openWorkspace(at: workspaceURL)
            }
        }
    }

    func createUITestWorkspace() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioUITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let swiftFile = tempDir.appendingPathComponent("TestFile.swift")
        let content = """
        import Foundation

        struct UITestStruct {
            let value: String
        }
        """
        try content.write(to: swiftFile, atomically: true, encoding: .utf8)

        // A `.swiftlint.yml` for the workspace, when the test supplies one.
        if let config = ProcessInfo.processInfo.environment["UI_TEST_CONFIG"] {
            try config.write(
                to: tempDir.appendingPathComponent(".swiftlint.yml"),
                atomically: true,
                encoding: .utf8
            )
        }
        return tempDir
    }
}
