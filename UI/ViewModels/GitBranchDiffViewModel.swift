//
//  GitBranchDiffViewModel.swift
//  SwiftLintRuleStudio
//
//  View model for git branch config comparison
//

import Foundation
import Observation

@MainActor
@Observable
class GitBranchDiffViewModel {
    var availableRefs: GitRefs?
    var selectedRef: String?
    var selectedRefString: String {
        get { selectedRef ?? "" }
        set { selectedRef = newValue.isEmpty ? nil : newValue }
    }
    var comparisonResult: ConfigComparisonResult?
    var isLoading: Bool = false
    var isNotGitRepo: Bool = false
    var error: Error?

    private let service: GitBranchDiffServiceProtocol
    private let workspacePath: URL?
    private let configRelativePath: String

    init(
        service: GitBranchDiffServiceProtocol,
        workspacePath: URL?,
        configRelativePath: String = ".swiftlint.yml"
    ) {
        self.service = service
        self.workspacePath = workspacePath
        self.configRelativePath = configRelativePath
    }

    func loadRefs() {
        guard let workspacePath = workspacePath else {
            isNotGitRepo = true
            return
        }

        isLoading = true
        error = nil
        isNotGitRepo = false

        Task {
            do {
                availableRefs = try await service.listAvailableRefs(at: workspacePath)
            } catch is GitBranchDiffError {
                isNotGitRepo = true
            } catch {
                self.error = error
            }
            isLoading = false
        }
    }

    func compareWithSelected() {
        guard let workspacePath = workspacePath,
              let selectedRef = selectedRef else { return }

        isLoading = true
        error = nil
        comparisonResult = nil

        Task {
            do {
                comparisonResult = try await service.compareConfigWithBranch(
                    repoPath: workspacePath,
                    branch: selectedRef,
                    configRelativePath: configRelativePath
                )
            } catch {
                self.error = error
            }
            isLoading = false
        }
    }
}
