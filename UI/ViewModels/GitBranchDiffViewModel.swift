//
//  GitBranchDiffViewModel.swift
//  SwiftLintRuleStudio
//
//  View model for git branch config comparison
//

import Foundation
import Combine

@MainActor
class GitBranchDiffViewModel: ObservableObject {
    @Published var availableRefs: GitRefs?
    @Published var selectedRef: String?
    @Published var comparisonResult: ConfigComparisonResult?
    @Published var isLoading: Bool = false
    @Published var isNotGitRepo: Bool = false
    @Published var error: Error?

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
