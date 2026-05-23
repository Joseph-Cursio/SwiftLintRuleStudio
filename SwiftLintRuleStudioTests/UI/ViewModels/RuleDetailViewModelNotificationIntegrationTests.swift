//
//  RuleDetailViewModelNotificationIntegrationTests.swift
//  SwiftLintRuleStudioTests
//
//  Notification integration tests
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct RuleDetailViewModelNotificationIntegrationTests {
    @Test("RuleDetailViewModel posts notification when configuration is saved")
    func testRuleDetailViewModelPostsNotification() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let configPath = try RuleDetailViewModelIntegrationTestHelpers.createConfigFile(
            in: tempDir,
            content: "rules: {}"
        )
        let yamlEngine = await RuleDetailViewModelIntegrationTestHelpers.createYAMLConfigurationEngine(
            configPath: configPath
        )

        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailViewModelIntegrationTestHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        @MainActor
        class CallbackTracker {
            var notificationReceived = false
            var receivedRuleId: String?
        }
        let tracker = await MainActor.run { CallbackTracker() }
        let expectedRuleId = await MainActor.run { rule.id }

        let observer = NotificationCenter.default.addObserver(
            forName: .ruleConfigurationDidChange,
            object: nil,
            queue: .main
        ) { notification in
            if let ruleId = notification.userInfo?["ruleId"] as? String, ruleId == expectedRuleId {
                tracker.notificationReceived = true
                tracker.receivedRuleId = ruleId
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        try await Task { @MainActor in
            try viewModel.loadConfiguration()
            viewModel.updateEnabled(true)
            viewModel.updateSeverity(.error)
            try viewModel.saveConfiguration()
        }.value

        _ = await UIAsyncTestHelpers.waitForConditionAsync(timeout: 1.0) {
            await tracker.notificationReceived
        }

        let notificationReceived = await tracker.notificationReceived
        let receivedRuleId = await tracker.receivedRuleId
        #expect(notificationReceived)
        #expect(receivedRuleId == "test_rule")
    }
}
