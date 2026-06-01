//
//  ConfigComparisonViewModelSelectTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for ConfigComparisonViewModel file-selection (selectLeft/Right) behavior,
//  using an injected fileSelector to stand in for the NSOpenPanel modal.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
private struct StubConfigComparisonService: ConfigComparisonServiceProtocol {
    func compare(
        config1 _: URL,
        label1 _: String,
        config2 _: URL,
        label2 _: String
    ) throws -> ConfigComparisonResult {
        ConfigComparisonResult(
            onlyInFirst: [], onlyInSecond: [], inBothDifferent: [], inBothSame: [],
            diff: YAMLConfigurationEngine.ConfigDiff(
                addedRules: [], removedRules: [], modifiedRules: [], before: "", after: ""
            )
        )
    }
}

@MainActor
struct ConfigComparisonViewModelSelectTests {

    private static let leftPath = URL(fileURLWithPath: "/project/left/.swiftlint.yml")
    private static let rightPath = URL(fileURLWithPath: "/project/right/.swiftlint.yml")

    private func makeResult() -> ConfigComparisonResult {
        ConfigComparisonResult(
            onlyInFirst: ["rule_a"], onlyInSecond: [], inBothDifferent: [], inBothSame: [],
            diff: YAMLConfigurationEngine.ConfigDiff(
                addedRules: [], removedRules: [], modifiedRules: [], before: "", after: ""
            )
        )
    }

    @Test("selectLeftWorkspace() stores the picked path and clears prior result")
    func testSelectLeftWorkspaceStoresPathAndClearsResult() {
        var callCount = 0
        let viewModel = ConfigComparisonViewModel(
            service: StubConfigComparisonService(),
            currentWorkspace: nil
        ) {
            callCount += 1
            return Self.leftPath
        }
        viewModel.comparisonResult = makeResult()

        viewModel.selectLeftWorkspace()

        #expect(callCount == 1)
        #expect(viewModel.leftWorkspacePath == Self.leftPath)
        #expect(viewModel.comparisonResult == nil)
    }

    @Test("selectRightWorkspace() stores the picked path and clears prior result")
    func testSelectRightWorkspaceStoresPathAndClearsResult() {
        var callCount = 0
        let viewModel = ConfigComparisonViewModel(
            service: StubConfigComparisonService(),
            currentWorkspace: nil
        ) {
            callCount += 1
            return Self.rightPath
        }
        viewModel.comparisonResult = makeResult()

        viewModel.selectRightWorkspace()

        #expect(callCount == 1)
        #expect(viewModel.rightWorkspacePath == Self.rightPath)
        #expect(viewModel.comparisonResult == nil)
    }

    @Test("selectLeftWorkspace() with a cancelled picker leaves state untouched")
    func testSelectLeftWorkspaceCancelledLeavesStateUntouched() {
        let viewModel = ConfigComparisonViewModel(
            service: StubConfigComparisonService(),
            currentWorkspace: nil
        ) {
            nil
        }
        viewModel.leftWorkspacePath = Self.leftPath
        viewModel.comparisonResult = makeResult()

        viewModel.selectLeftWorkspace()

        // Cancelling the panel must not overwrite the path or clear the result.
        #expect(viewModel.leftWorkspacePath == Self.leftPath)
        #expect(viewModel.comparisonResult != nil)
    }

    @Test("selectRightWorkspace() with a cancelled picker leaves state untouched")
    func testSelectRightWorkspaceCancelledLeavesStateUntouched() {
        let viewModel = ConfigComparisonViewModel(
            service: StubConfigComparisonService(),
            currentWorkspace: nil
        ) {
            nil
        }
        viewModel.rightWorkspacePath = Self.rightPath
        viewModel.comparisonResult = makeResult()

        viewModel.selectRightWorkspace()

        #expect(viewModel.rightWorkspacePath == Self.rightPath)
        #expect(viewModel.comparisonResult != nil)
    }
}
