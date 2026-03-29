//
//  GitBranchDiffViewModelTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for GitBranchDiffViewModel state management and service delegation
//

import Testing
import Foundation
@testable import SwiftLintRuleStudioCore
@testable import SwiftLintRuleStudio

@MainActor
struct GitBranchDiffViewModelTests {

    // MARK: - Helpers

    private static let workspacePath = URL(fileURLWithPath: "/project/MyApp")

    private func makeRefs(
        currentBranch: String = "main",
        branches: [String] = ["main", "develop"],
        tags: [String] = ["v1.0"]
    ) -> GitRefs {
        GitRefs(currentBranch: currentBranch, branches: branches, tags: tags)
    }

    private func makeComparisonResult() -> ConfigComparisonResult {
        ConfigComparisonResult(
            onlyInFirst: [], onlyInSecond: ["new_rule"],
            inBothDifferent: [], inBothSame: [],
            diff: YAMLConfigurationEngine.ConfigDiff(
                addedRules: ["new_rule"], removedRules: [], modifiedRules: [], before: "", after: ""
            )
        )
    }

    // MARK: - Initial State

    @Test("Initial state has nil refs, no selection, not loading, not flagged as non-git-repo")
    func testInitialState() {
        let service = SpyGitBranchDiffService()
        let viewModel = GitBranchDiffViewModel(service: service, workspacePath: Self.workspacePath)

        #expect(viewModel.availableRefs == nil)
        #expect(viewModel.selectedRef == nil)
        #expect(viewModel.comparisonResult == nil)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.isNotGitRepo == false)
        #expect(viewModel.error == nil)
    }

    // MARK: - loadRefs()

    @Test("loadRefs with nil workspacePath sets isNotGitRepo synchronously without calling service")
    func testLoadRefsWithNilWorkspacePathSetsIsNotGitRepo() {
        let service = SpyGitBranchDiffService()
        let viewModel = GitBranchDiffViewModel(service: service, workspacePath: nil)

        viewModel.loadRefs()

        #expect(viewModel.isNotGitRepo)
        #expect(service.listRefsCallCount == 0)
    }

    @Test("loadRefs populates availableRefs on success")
    func testLoadRefsPopulatesAvailableRefs() async throws {
        let refs = makeRefs()
        let service = SpyGitBranchDiffService(refsToReturn: refs)
        let viewModel = GitBranchDiffViewModel(service: service, workspacePath: Self.workspacePath)

        viewModel.loadRefs()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(service.listRefsCallCount == 1)
        #expect(viewModel.availableRefs?.currentBranch == "main")
        #expect(viewModel.availableRefs?.branches == ["main", "develop"])
        #expect(viewModel.isLoading == false)
        #expect(viewModel.isNotGitRepo == false)
    }

    @Test("loadRefs with GitBranchDiffError sets isNotGitRepo (not error property)")
    func testLoadRefsGitBranchDiffErrorSetsIsNotGitRepo() async throws {
        let service = SpyGitBranchDiffService(errorToThrow: GitBranchDiffError.notGitRepo)
        let viewModel = GitBranchDiffViewModel(service: service, workspacePath: Self.workspacePath)

        viewModel.loadRefs()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.isNotGitRepo)
        #expect(viewModel.error == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test("loadRefs with configNotFoundOnBranch error also sets isNotGitRepo")
    func testLoadRefsConfigNotFoundSetsIsNotGitRepo() async throws {
        let service = SpyGitBranchDiffService(
            errorToThrow: GitBranchDiffError.configNotFoundOnBranch(branch: "feature")
        )
        let viewModel = GitBranchDiffViewModel(service: service, workspacePath: Self.workspacePath)

        viewModel.loadRefs()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.isNotGitRepo)
        #expect(viewModel.error == nil)
    }

    @Test("loadRefs with non-GitBranchDiffError sets error property")
    func testLoadRefsNonGitErrorSetsError() async throws {
        let service = SpyGitBranchDiffService(
            errorToThrow: NSError(domain: "SpyError", code: 99, userInfo: nil)
        )
        let viewModel = GitBranchDiffViewModel(service: service, workspacePath: Self.workspacePath)

        viewModel.loadRefs()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.error != nil)
        #expect(viewModel.isNotGitRepo == false)
    }

    @Test("loadRefs clears isLoading after task completes")
    func testLoadRefsClearsIsLoading() async throws {
        let service = SpyGitBranchDiffService(refsToReturn: makeRefs())
        let viewModel = GitBranchDiffViewModel(service: service, workspacePath: Self.workspacePath)

        viewModel.loadRefs()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.isLoading == false)
    }

    // MARK: - compareWithSelected()

    @Test("compareWithSelected with nil selectedRef does not call service")
    func testCompareWithNilSelectedRefDoesNothing() {
        let service = SpyGitBranchDiffService()
        let viewModel = GitBranchDiffViewModel(service: service, workspacePath: Self.workspacePath)
        viewModel.selectedRef = nil

        viewModel.compareWithSelected()

        #expect(service.compareCallCount == 0)
        #expect(viewModel.comparisonResult == nil)
    }

    @Test("compareWithSelected calls service with selectedRef and populates comparisonResult")
    func testCompareWithSelectedCallsService() async throws {
        let result = makeComparisonResult()
        let service = SpyGitBranchDiffService(refsToReturn: makeRefs(), comparisonResultToReturn: result)
        let viewModel = GitBranchDiffViewModel(service: service, workspacePath: Self.workspacePath)
        viewModel.selectedRef = "develop"

        viewModel.compareWithSelected()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(service.compareCallCount == 1)
        #expect(service.lastComparedBranch == "develop")
        #expect(viewModel.comparisonResult?.onlyInSecond == ["new_rule"])
        #expect(viewModel.isLoading == false)
    }

    @Test("compareWithSelected passes correct configRelativePath to service")
    func testCompareWithSelectedPassesConfigRelativePath() async throws {
        let service = SpyGitBranchDiffService(comparisonResultToReturn: makeComparisonResult())
        let viewModel = GitBranchDiffViewModel(
            service: service,
            workspacePath: Self.workspacePath,
            configRelativePath: ".config/.swiftlint.yml"
        )
        viewModel.selectedRef = "main"

        viewModel.compareWithSelected()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(service.lastCompareConfigPath == ".config/.swiftlint.yml")
    }

    @Test("compareWithSelected on service error stores error property")
    func testCompareWithSelectedErrorSetsError() async throws {
        let service = SpyGitBranchDiffService(
            compareErrorToThrow: NSError(domain: "SpyError", code: 1, userInfo: nil)
        )
        let viewModel = GitBranchDiffViewModel(service: service, workspacePath: Self.workspacePath)
        viewModel.selectedRef = "develop"

        viewModel.compareWithSelected()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.error != nil)
        #expect(viewModel.comparisonResult == nil)
        #expect(viewModel.isLoading == false)
    }
}

// MARK: - Spy

private final class SpyGitBranchDiffService: GitBranchDiffServiceProtocol, @unchecked Sendable {
    private let refsToReturn: GitRefs?
    private let comparisonResultToReturn: ConfigComparisonResult?
    private let errorToThrow: Error?
    private let compareErrorToThrow: Error?

    var listRefsCallCount = 0
    var compareCallCount = 0
    var lastComparedBranch: String?
    var lastCompareConfigPath: String?

    init(
        refsToReturn: GitRefs? = nil,
        comparisonResultToReturn: ConfigComparisonResult? = nil,
        errorToThrow: Error? = nil,
        compareErrorToThrow: Error? = nil
    ) {
        self.refsToReturn = refsToReturn
        self.comparisonResultToReturn = comparisonResultToReturn
        self.errorToThrow = errorToThrow
        self.compareErrorToThrow = compareErrorToThrow
    }

    func listAvailableRefs(at repoPath: URL) throws -> GitRefs {
        listRefsCallCount += 1
        if let error = errorToThrow {
            throw error
        }
        return refsToReturn ?? GitRefs(currentBranch: "main", branches: ["main"], tags: [])
    }

    func compareConfigWithBranch(
        repoPath: URL,
        branch: String,
        configRelativePath: String
    ) throws -> ConfigComparisonResult {
        compareCallCount += 1
        lastComparedBranch = branch
        lastCompareConfigPath = configRelativePath
        if let error = compareErrorToThrow {
            throw error
        }
        return comparisonResultToReturn ?? ConfigComparisonResult(
            onlyInFirst: [], onlyInSecond: [], inBothDifferent: [], inBothSame: [],
            diff: YAMLConfigurationEngine.ConfigDiff(
                addedRules: [], removedRules: [], modifiedRules: [], before: "", after: ""
            )
        )
    }
}
