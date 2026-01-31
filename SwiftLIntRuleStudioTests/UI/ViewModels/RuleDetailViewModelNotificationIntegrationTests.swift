//
//  RuleDetailViewModelNotificationIntegrationTests.swift
//  SwiftLIntRuleStudioTests
//
//  Notification integration tests
//

import Foundation
import Testing
@testable import SwiftLIntRuleStudio

struct RuleDetailVMNotificationIntegrationTests {
    @Test("RuleDetailViewModel posts notification when configuration is saved")
    func testRuleDetailViewModelPostsNotification() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }

        let configPath = try RuleDetailVMIntegrationHelpers.createConfigFile(
            in: tempDir,
            content: "rules: {}"
        )
        let yamlEngine = await RuleDetailVMIntegrationHelpers.createYAMLConfigurationEngine(
            configPath: configPath
        )

        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "test_rule", isOptIn: false)
        let viewModel = await RuleDetailVMIntegrationHelpers.createRuleDetailViewModel(
            rule: rule,
            yamlEngine: yamlEngine
        )

        var notificationReceived = false
        var receivedRuleId: String?
        let expectedRuleId = await MainActor.run { rule.id }

        let observer = NotificationCenter.default.addObserver(
            forName: .ruleConfigurationDidChange,
            object: nil,
            queue: .main
        ) { notification in
            if let ruleId = notification.userInfo?["ruleId"] as? String, ruleId == expectedRuleId {
                notificationReceived = true
                receivedRuleId = ruleId
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        try await Task { @MainActor in
            try viewModel.loadConfiguration()
            viewModel.updateEnabled(true)
            viewModel.updateSeverity(.error)
            try await viewModel.saveConfiguration()
        }.value

        _ = await UIAsyncTestHelpers.waitForConditionAsync(timeout: 1.0) {
            notificationReceived
        }

        #expect(notificationReceived == true)
        #expect(receivedRuleId == "test_rule")
    }
}
