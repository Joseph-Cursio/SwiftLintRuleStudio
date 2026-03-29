//
//  GitBranchDiffService.swift
//  SwiftLintRuleStudio
//
//  Service for comparing .swiftlint.yml between git branches
//

import Foundation

// MARK: - Types

public struct GitRefs: Sendable {
    public let currentBranch: String
    public let branches: [String]
    public let tags: [String]

    public init(
        currentBranch: String,
        branches: [String],
        tags: [String]
    ) {
        self.currentBranch = currentBranch
        self.branches = branches
        self.tags = tags
    }
}

// MARK: - Protocol

public protocol GitBranchDiffServiceProtocol: Sendable {
    func listAvailableRefs(at repoPath: URL) async throws -> GitRefs
    func compareConfigWithBranch(
        repoPath: URL,
        branch: String,
        configRelativePath: String
    ) async throws -> ConfigComparisonResult
}

// MARK: - Errors

public enum GitBranchDiffError: LocalizedError, Sendable {
    case notGitRepo
    case configNotFoundOnBranch(branch: String)
    case comparisonFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notGitRepo:
            return "The workspace is not a git repository."
        case .configNotFoundOnBranch(let branch):
            return "No .swiftlint.yml found on branch '\(branch)'."
        case .comparisonFailed(let msg):
            return "Comparison failed: \(msg)"
        }
    }
}

// MARK: - Implementation

public final class GitBranchDiffService: GitBranchDiffServiceProtocol, Sendable {
    private let gitService: GitServiceProtocol
    private let _comparisonService: ConfigComparisonServiceProtocol?

    public init(
        gitService: GitServiceProtocol? = nil,
        comparisonService: ConfigComparisonServiceProtocol? = nil
    ) {
        self.gitService = gitService ?? GitServiceActor()
        // comparisonService requires @MainActor init, so we store it lazily
        self._comparisonService = comparisonService
    }

    private var resolvedComparisonService: ConfigComparisonServiceProtocol {
        get async {
            if let svc = _comparisonService { return svc }
            return await MainActor.run { ConfigComparisonService() }
        }
    }

    public func listAvailableRefs(at repoPath: URL) async throws -> GitRefs {
        let isRepo = try await gitService.isGitRepository(at: repoPath)
        guard isRepo else { throw GitBranchDiffError.notGitRepo }

        let currentBranch = try await gitService.getCurrentBranch(at: repoPath)
        let branches = try await gitService.listBranches(at: repoPath)
        let tags = try await gitService.listTags(at: repoPath)

        return GitRefs(currentBranch: currentBranch, branches: branches, tags: tags)
    }

    public func compareConfigWithBranch(
        repoPath: URL,
        branch: String,
        configRelativePath: String
    ) async throws -> ConfigComparisonResult {
        // Get config content from the selected branch
        let branchContent: String
        do {
            branchContent = try await gitService.showFile(
                at: repoPath, branch: branch, filePath: configRelativePath
            )
        } catch {
            throw GitBranchDiffError.configNotFoundOnBranch(branch: branch)
        }

        // Write to temp file for comparison
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitBranchDiff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let branchConfigFile = tempDir.appendingPathComponent(".swiftlint.yml")
        try branchContent.write(to: branchConfigFile, atomically: true, encoding: .utf8)

        let currentConfigPath = repoPath.appendingPathComponent(configRelativePath)

        let svc = await resolvedComparisonService
        return try await MainActor.run {
            try svc.compare(
                config1: currentConfigPath,
                label1: "Current",
                config2: branchConfigFile,
                label2: branch
            )
        }
    }
}
