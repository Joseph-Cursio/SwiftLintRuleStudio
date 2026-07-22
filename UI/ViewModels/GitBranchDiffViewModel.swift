//
//  GitBranchDiffViewModel.swift
//  SwiftLintRuleStudio
//
//  View model for git branch config comparison
//

import Foundation
import Observation
import SwiftLintRuleStudioCore

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

    /// The in-flight ref listing / branch comparison, if any. Each is cancelled
    /// and replaced on re-invocation so a superseded run cannot overwrite the
    /// newer one's result.
    @ObservationIgnored private(set) var loadRefsTask: Task<Void, Never>?
    @ObservationIgnored private(set) var compareTask: Task<Void, Never>?

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

        loadRefsTask?.cancel()
        isLoading = true
        error = nil
        isNotGitRepo = false

        loadRefsTask = Task {
            do {
                let refs = try await service.listAvailableRefs(at: workspacePath)
                // Superseded by a newer load — leave the newer run's state alone.
                guard !Task.isCancelled else { return }
                availableRefs = refs
            } catch is GitBranchDiffError {
                guard !Task.isCancelled else { return }
                isNotGitRepo = true
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error
            }
            guard !Task.isCancelled else { return }
            isLoading = false
        }
    }

    func compareWithSelected() {
        guard let workspacePath = workspacePath,
              let selectedRef = selectedRef else { return }

        compareTask?.cancel()
        isLoading = true
        error = nil
        comparisonResult = nil

        compareTask = Task {
            do {
                let result = try await service.compareConfigWithBranch(
                    repoPath: workspacePath,
                    branch: selectedRef,
                    configRelativePath: configRelativePath
                )
                // Superseded by a newer comparison — leave the newer run's state alone.
                guard !Task.isCancelled else { return }
                comparisonResult = result
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error
            }
            guard !Task.isCancelled else { return }
            isLoading = false
        }
    }
}
