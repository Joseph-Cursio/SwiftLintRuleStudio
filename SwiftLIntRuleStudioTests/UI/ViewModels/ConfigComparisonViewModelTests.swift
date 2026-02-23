//
//  ConfigComparisonViewModelTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for ConfigComparisonViewModel state management and service delegation
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

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
        let vm = ConfigComparisonViewModel(service: service, currentWorkspace: workspace)

        #expect(vm.leftWorkspacePath == workspace.configPath)
        #expect(vm.rightWorkspacePath == nil)
        #expect(vm.comparisonResult == nil)
        #expect(!vm.isComparing)
        #expect(vm.error == nil)
    }

    @Test("Init with nil workspace leaves both paths nil")
    func testInitWithNilWorkspaceLeavesPathsNil() {
        let service = SpyConfigComparisonService()
        let vm = ConfigComparisonViewModel(service: service, currentWorkspace: nil)

        #expect(vm.leftWorkspacePath == nil)
        #expect(vm.rightWorkspacePath == nil)
    }

    // MARK: - compare()

    @Test("compare() with both paths set calls service and populates comparisonResult")
    func testCompareWithBothPathsCallsService() {
        let result = makeResult()
        let service = SpyConfigComparisonService(resultToReturn: result)
        let vm = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        vm.leftWorkspacePath = Self.leftPath
        vm.rightWorkspacePath = Self.rightPath

        vm.compare()

        #expect(service.compareCallCount == 1)
        #expect(vm.comparisonResult != nil)
        #expect(vm.comparisonResult?.onlyInFirst == ["rule_a"])
        #expect(vm.error == nil)
    }

    @Test("compare() with missing leftWorkspacePath does not call service")
    func testCompareWithMissingLeftPathDoesNothing() {
        let service = SpyConfigComparisonService()
        let vm = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        vm.rightWorkspacePath = Self.rightPath

        vm.compare()

        #expect(service.compareCallCount == 0)
        #expect(vm.comparisonResult == nil)
    }

    @Test("compare() with missing rightWorkspacePath does not call service")
    func testCompareWithMissingRightPathDoesNothing() {
        let service = SpyConfigComparisonService()
        let vm = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        vm.leftWorkspacePath = Self.leftPath

        vm.compare()

        #expect(service.compareCallCount == 0)
        #expect(vm.comparisonResult == nil)
    }

    @Test("compare() on service error stores error and leaves comparisonResult nil")
    func testCompareServiceErrorSetsError() {
        let service = SpyConfigComparisonService(shouldThrow: true)
        let vm = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        vm.leftWorkspacePath = Self.leftPath
        vm.rightWorkspacePath = Self.rightPath

        vm.compare()

        #expect(vm.error != nil)
        #expect(vm.comparisonResult == nil)
    }

    @Test("compare() clears isComparing after successful completion")
    func testCompareIsComparingClearedOnSuccess() {
        let service = SpyConfigComparisonService(resultToReturn: makeResult())
        let vm = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        vm.leftWorkspacePath = Self.leftPath
        vm.rightWorkspacePath = Self.rightPath

        vm.compare()

        #expect(!vm.isComparing)
    }

    @Test("compare() clears isComparing after service error")
    func testCompareIsComparingClearedOnError() {
        let service = SpyConfigComparisonService(shouldThrow: true)
        let vm = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        vm.leftWorkspacePath = Self.leftPath
        vm.rightWorkspacePath = Self.rightPath

        vm.compare()

        #expect(!vm.isComparing)
    }

    @Test("compare() passes the correct label derived from parent directory name")
    func testComparePassesCorrectLabels() {
        let service = SpyConfigComparisonService(resultToReturn: makeResult())
        let vm = ConfigComparisonViewModel(service: service, currentWorkspace: nil)
        vm.leftWorkspacePath = Self.leftPath
        vm.rightWorkspacePath = Self.rightPath

        vm.compare()

        #expect(service.lastLabel1 == "left")
        #expect(service.lastLabel2 == "right")
    }
}

// MARK: - Spy

@MainActor
private final class SpyConfigComparisonService: ConfigComparisonServiceProtocol {
    private let resultToReturn: ConfigComparisonResult?
    private let shouldThrow: Bool

    var compareCallCount = 0
    var lastLabel1: String?
    var lastLabel2: String?

    init(
        resultToReturn: ConfigComparisonResult? = nil,
        shouldThrow: Bool = false
    ) {
        self.resultToReturn = resultToReturn
        self.shouldThrow = shouldThrow
    }

    func compare(config1: URL, label1: String, config2: URL, label2: String) throws -> ConfigComparisonResult {
        compareCallCount += 1
        lastLabel1 = label1
        lastLabel2 = label2
        if shouldThrow {
            throw NSError(domain: "SpyError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Comparison failed"])
        }
        return resultToReturn ?? ConfigComparisonResult(
            onlyInFirst: [], onlyInSecond: [], inBothDifferent: [], inBothSame: [],
            diff: YAMLConfigurationEngine.ConfigDiff(
                addedRules: [], removedRules: [], modifiedRules: [], before: "", after: "")
        )
    }
}
