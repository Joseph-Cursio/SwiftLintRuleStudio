//
//  ConfigComparisonViewModelTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for ConfigComparisonViewModel state management and service delegation
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
private final class SpyConfigComparisonService: ConfigComparisonServiceProtocol {
    private let resultToReturn: ConfigComparisonResult?
    private let shouldThrow: Bool

    var nextResult: ConfigComparisonResult?
    var compareCallCount = 0
    var lastLabel1: String?
    var lastLabel2: String?
    var lastConfig1: URL?
    var lastConfig2: URL?
    var compareHook: (() -> Void)?

    init(
        resultToReturn: ConfigComparisonResult? = nil,
        shouldThrow: Bool = false
    ) {
        self.resultToReturn = resultToReturn
        self.shouldThrow = shouldThrow
    }

    func compare(
        config1: URL,
        label1: String,
        config2: URL,
        label2: String
    ) throws -> ConfigComparisonResult {
        compareCallCount += 1
        lastConfig1 = config1
        lastConfig2 = config2
        lastLabel1 = label1
        lastLabel2 = label2
        compareHook?()
        if shouldThrow {
            throw NSError(
                domain: "SpyError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Comparison failed"]
            )
        }
        if let queued = nextResult {
            nextResult = nil
            return queued
        }
        return resultToReturn ?? ConfigComparisonResult(
            onlyInFirst: [], onlyInSecond: [], inBothDifferent: [], inBothSame: [],
            diff: YAMLConfigurationEngine.ConfigDiff(
                addedRules: [], removedRules: [], modifiedRules: [], before: "", after: "")
        )
    }
}

@MainActor
struct ConfigComparisonViewModelTests {

    // MARK: - Helpers

    private func makeResult() -> ConfigComparisonResult {
        ConfigComparisonResult(
            onlyInFirst: ["rule_a"],
            onlyInSecond: [],
            inBothDifferent: [],
            inBothSame: [],
            diff: YAMLConfigurationEngine.ConfigDiff(
                addedRules: [], removedRules: [], modifiedRules: [], before: "", after: ""
            )
        )
    }

    private static let leftPath = URL(fileURLWithPath: "/project/left/.swiftlint.yml")
    private static let rightPath = URL(fileURLWithPath: "/project/right/.swiftlint.yml")

    // MARK: - Initialization

    @Test("Init with workspace that has a configPath pre-fills leftWorkspacePath")
    func testInitWithCurrentWorkspaceSetsLeftPath() {
        let workspaceDir = URL(fileURLWithPath: "/project/left")
        let workspace = Workspace(path: workspaceDir)
        let service = SpyConfigComparisonService()
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: workspace)

        #expect(viewModel.leftWorkspacePath == workspace.configPath)
        #expect(viewModel.rightWorkspacePath == nil)
        #expect(viewModel.comparisonResult == nil)
        #expect(viewModel.isComparing == false)
        #expect(viewModel.error == nil)
    }

    @Test("Init with nil workspace leaves both paths nil")
    func testInitWithNilWorkspaceLeavesPathsNil() {
        let service = SpyConfigComparisonService()
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)

        #expect(viewModel.leftWorkspacePath == nil)
        #expect(viewModel.rightWorkspacePath == nil)
    }

    // MARK: - compare()

    @Test("compare() with both paths set calls service and populates comparisonResult")
    func testCompareWithBothPathsCallsService() {
        let result = makeResult()
        let service = SpyConfigComparisonService(resultToReturn: result)
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        viewModel.leftWorkspacePath = Self.leftPath
        viewModel.rightWorkspacePath = Self.rightPath

        viewModel.compare()

        #expect(service.compareCallCount == 1)
        #expect(viewModel.comparisonResult != nil)
        #expect(viewModel.comparisonResult?.onlyInFirst == ["rule_a"])
        #expect(viewModel.error == nil)
    }

    @Test("compare() with missing leftWorkspacePath does not call service")
    func testCompareWithMissingLeftPathDoesNothing() {
        let service = SpyConfigComparisonService()
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        viewModel.rightWorkspacePath = Self.rightPath

        viewModel.compare()

        #expect(service.compareCallCount == 0)
        #expect(viewModel.comparisonResult == nil)
    }

    @Test("compare() with missing rightWorkspacePath does not call service")
    func testCompareWithMissingRightPathDoesNothing() {
        let service = SpyConfigComparisonService()
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        viewModel.leftWorkspacePath = Self.leftPath

        viewModel.compare()

        #expect(service.compareCallCount == 0)
        #expect(viewModel.comparisonResult == nil)
    }

    @Test("compare() on service error stores error and leaves comparisonResult nil")
    func testCompareServiceErrorSetsError() {
        let service = SpyConfigComparisonService(shouldThrow: true)
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        viewModel.leftWorkspacePath = Self.leftPath
        viewModel.rightWorkspacePath = Self.rightPath

        viewModel.compare()

        #expect(viewModel.error != nil)
        #expect(viewModel.comparisonResult == nil)
    }

    @Test("compare() clears isComparing after successful completion")
    func testCompareIsComparingClearedOnSuccess() {
        let service = SpyConfigComparisonService(resultToReturn: makeResult())
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        viewModel.leftWorkspacePath = Self.leftPath
        viewModel.rightWorkspacePath = Self.rightPath

        viewModel.compare()

        #expect(viewModel.isComparing == false)
    }

    @Test("compare() clears isComparing after service error")
    func testCompareIsComparingClearedOnError() {
        let service = SpyConfigComparisonService(shouldThrow: true)
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        viewModel.leftWorkspacePath = Self.leftPath
        viewModel.rightWorkspacePath = Self.rightPath

        viewModel.compare()

        #expect(viewModel.isComparing == false)
    }

    @Test("compare() passes the correct label derived from parent directory name")
    func testComparePassesCorrectLabels() {
        let service = SpyConfigComparisonService(resultToReturn: makeResult())
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        viewModel.leftWorkspacePath = Self.leftPath
        viewModel.rightWorkspacePath = Self.rightPath

        viewModel.compare()

        #expect(service.lastLabel1 == "left")
        #expect(service.lastLabel2 == "right")
    }

    // MARK: - Initialization edge cases

    @Test("Init with workspace whose configPath is nil leaves leftWorkspacePath nil")
    func testInitWithWorkspaceMissingConfigPathLeavesLeftPathNil() {
        let workspaceDir = URL(fileURLWithPath: "/project/no-config")
        var workspace = Workspace(path: workspaceDir)
        workspace.configPath = nil
        let service = SpyConfigComparisonService()

        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: workspace)

        #expect(viewModel.leftWorkspacePath == nil)
        #expect(viewModel.rightWorkspacePath == nil)
        #expect(viewModel.comparisonResult == nil)
    }

    // MARK: - compare() additional branches

    @Test("compare() with both paths nil does not call service and leaves state untouched")
    func testCompareWithBothPathsNilDoesNothing() {
        let service = SpyConfigComparisonService(resultToReturn: makeResult())
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)

        viewModel.compare()

        #expect(service.compareCallCount == 0)
        #expect(viewModel.comparisonResult == nil)
        #expect(viewModel.error == nil)
        #expect(viewModel.isComparing == false)
    }

    @Test("compare() forwards exact URL values to the service")
    func testComparePassesURLsThrough() {
        let service = SpyConfigComparisonService(resultToReturn: makeResult())
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        viewModel.leftWorkspacePath = Self.leftPath
        viewModel.rightWorkspacePath = Self.rightPath

        viewModel.compare()

        #expect(service.lastConfig1 == Self.leftPath)
        #expect(service.lastConfig2 == Self.rightPath)
    }

    @Test("compare() clears a previously stored error on a successful run")
    func testCompareClearsPriorErrorOnSuccess() {
        let service = SpyConfigComparisonService(resultToReturn: makeResult())
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        viewModel.leftWorkspacePath = Self.leftPath
        viewModel.rightWorkspacePath = Self.rightPath
        viewModel.error = NSError(domain: "Stale", code: 99)

        viewModel.compare()

        #expect(viewModel.error == nil)
        #expect(viewModel.comparisonResult != nil)
    }

    @Test("compare() clears a previously stored error even when next run also throws")
    func testCompareClearsPriorErrorBeforeNextThrow() {
        let originalError = NSError(domain: "Original", code: 7)
        let service = SpyConfigComparisonService(shouldThrow: true)
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        viewModel.leftWorkspacePath = Self.leftPath
        viewModel.rightWorkspacePath = Self.rightPath
        viewModel.error = originalError

        viewModel.compare()

        // The error is reset to nil, then re-populated with the new throw — so it
        // must NOT be the original instance.
        let newError = viewModel.error as NSError?
        #expect(newError?.domain != "Original")
        #expect(newError != nil)
    }

    @Test("compare() exposes isComparing == true while the service call is in flight")
    func testCompareIsComparingTrueDuringServiceCall() {
        let service = SpyConfigComparisonService(resultToReturn: makeResult())
        // nil distinguishes "hook never ran" from observed values
        // swiftlint:disable:next discouraged_optional_boolean
        var observedIsComparing: Bool?
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        viewModel.leftWorkspacePath = Self.leftPath
        viewModel.rightWorkspacePath = Self.rightPath
        service.compareHook = { observedIsComparing = viewModel.isComparing }

        viewModel.compare()

        #expect(observedIsComparing == true)
        #expect(viewModel.isComparing == false)
    }

    @Test("compare() clears isComparing AFTER the result has been stored")
    func testCompareResultStoredBeforeIsComparingClears() {
        let result = makeResult()
        let service = SpyConfigComparisonService(resultToReturn: result)
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        viewModel.leftWorkspacePath = Self.leftPath
        viewModel.rightWorkspacePath = Self.rightPath

        viewModel.compare()

        // Sequential implementation: by the time compare() returns,
        // both result is populated AND isComparing is false.
        #expect(viewModel.comparisonResult != nil)
        #expect(viewModel.isComparing == false)
    }

    @Test("compare() called twice overwrites previous comparisonResult with newest")
    func testCompareOverwritesPriorResult() {
        let firstResult = ConfigComparisonResult(
            onlyInFirst: ["first_run"], onlyInSecond: [], inBothDifferent: [], inBothSame: [],
            diff: YAMLConfigurationEngine.ConfigDiff(
                addedRules: [], removedRules: [], modifiedRules: [], before: "", after: ""
            )
        )
        let secondResult = ConfigComparisonResult(
            onlyInFirst: ["second_run"], onlyInSecond: [], inBothDifferent: [], inBothSame: [],
            diff: YAMLConfigurationEngine.ConfigDiff(
                addedRules: [], removedRules: [], modifiedRules: [], before: "", after: ""
            )
        )
        let service = SpyConfigComparisonService(resultToReturn: firstResult)
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        viewModel.leftWorkspacePath = Self.leftPath
        viewModel.rightWorkspacePath = Self.rightPath

        viewModel.compare()
        #expect(viewModel.comparisonResult?.onlyInFirst == ["first_run"])

        service.nextResult = secondResult
        viewModel.compare()

        #expect(service.compareCallCount == 2)
        #expect(viewModel.comparisonResult?.onlyInFirst == ["second_run"])
    }

    @Test("compare() label derivation uses immediate parent directory only, ignoring deeper ancestors")
    func testCompareLabelUsesOnlyImmediateParent() {
        let nestedLeft = URL(fileURLWithPath: "/orgs/acme/teams/ios/repoA/.swiftlint.yml")
        let nestedRight = URL(fileURLWithPath: "/orgs/acme/teams/ios/repoB/.swiftlint.yml")
        let service = SpyConfigComparisonService(resultToReturn: makeResult())
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        viewModel.leftWorkspacePath = nestedLeft
        viewModel.rightWorkspacePath = nestedRight

        viewModel.compare()

        #expect(service.lastLabel1 == "repoA")
        #expect(service.lastLabel2 == "repoB")
    }

    @Test("compare() error path stores the exact thrown error instance")
    func testCompareThrownErrorIsPropagatedUnchanged() {
        let service = SpyConfigComparisonService(shouldThrow: true)
        let viewModel = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        viewModel.leftWorkspacePath = Self.leftPath
        viewModel.rightWorkspacePath = Self.rightPath

        viewModel.compare()

        let nsError = viewModel.error as NSError?
        #expect(nsError?.domain == "SpyError")
        #expect(nsError?.code == 1)
    }
}
