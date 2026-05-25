//
//  GitBranchDiffViewTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector smoke test for GitBranchDiffView. Passing a nil
//  workspacePath drives the "Not a Git Repository" empty-state branch,
//  which doesn't need to talk to the service stub.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Foundation
import SwiftUI
import Testing
import ViewInspector

private struct StubGitBranchDiffService: GitBranchDiffServiceProtocol {
    func listAvailableRefs(at _: URL) async throws -> GitRefs {
        GitRefs(currentBranch: "main", branches: [], tags: [])
    }

    func compareConfigWithBranch(
        repoPath _: URL,
        branch _: String,
        configRelativePath _: String
    ) async throws -> ConfigComparisonResult {
        ConfigComparisonResult(
            onlyInFirst: [], onlyInSecond: [], inBothDifferent: [], inBothSame: [],
            diff: YAMLConfigurationEngine.ConfigDiff(
                addedRules: [], removedRules: [], modifiedRules: [],
                before: "", after: ""
            )
        )
    }
}

@MainActor
struct GitBranchDiffViewTests {
    @Test("GitBranchDiffView shows the not-a-git-repo empty state when given nil workspacePath")
    func testNotGitRepositoryEmptyState() async throws {
        let view = await MainActor.run {
            GitBranchDiffView(service: StubGitBranchDiffService(), workspacePath: nil)
        }

        let (hasHeader, hasBody) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            return (
                (try? inspector.find(text: "Not a Git Repository")) != nil,
                (try? inspector.find(text: "This workspace is not inside a git repository. Branch diff requires git.")) != nil
            )
        }

        #expect(hasHeader)
        #expect(hasBody)
    }
}
