//
//  GitService.swift
//  SwiftLintRuleStudio
//
//  Git command execution service for branch diff and version control operations
//

import Foundation

// MARK: - Protocol

protocol GitServiceProtocol: Sendable {
    func isGitRepository(at path: URL) async throws -> Bool
    func getCurrentBranch(at repoPath: URL) async throws -> String
    func listBranches(at repoPath: URL) async throws -> [String]
    func listTags(at repoPath: URL) async throws -> [String]
    func showFile(at repoPath: URL, branch: String, filePath: String) async throws -> String
    func diffFile(at repoPath: URL, fromRef: String, toRef: String, filePath: String) async throws -> String
}

// MARK: - Errors

enum GitServiceError: LocalizedError, Sendable {
    case notARepository
    case branchNotFound(String)
    case fileNotFound(branch: String, path: String)
    case executionFailed(message: String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notARepository:
            return "The specified directory is not a git repository."
        case .branchNotFound(let branch):
            return "Branch '\(branch)' not found."
        case .fileNotFound(let branch, let path):
            return "File '\(path)' not found on branch '\(branch)'."
        case .executionFailed(let message):
            return "Git command failed: \(message)"
        case .timeout:
            return "Git command timed out after 30 seconds."
        }
    }
}

// MARK: - Implementation

actor GitService: GitServiceProtocol {
    private let gitPath = URL(fileURLWithPath: "/usr/bin/git")
    private let timeoutSeconds: UInt64 = 30

    func isGitRepository(at path: URL) async throws -> Bool {
        do {
            let output = try await runGit(at: path, arguments: ["rev-parse", "--is-inside-work-tree"])
            return output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        } catch {
            return false
        }
    }

    func getCurrentBranch(at repoPath: URL) async throws -> String {
        try await ensureGitRepo(at: repoPath)
        let output = try await runGit(at: repoPath, arguments: ["rev-parse", "--abbrev-ref", "HEAD"])
        let branch = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if branch.isEmpty {
            throw GitServiceError.executionFailed(message: "Could not determine current branch.")
        }
        return branch
    }

    func listBranches(at repoPath: URL) async throws -> [String] {
        try await ensureGitRepo(at: repoPath)
        let output = try await runGit(at: repoPath, arguments: ["branch", "--format=%(refname:short)"])
        return output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func listTags(at repoPath: URL) async throws -> [String] {
        try await ensureGitRepo(at: repoPath)
        let output = try await runGit(at: repoPath, arguments: ["tag", "--list"])
        return output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func showFile(at repoPath: URL, branch: String, filePath: String) async throws -> String {
        try await ensureGitRepo(at: repoPath)
        do {
            let output = try await runGit(at: repoPath, arguments: ["show", "\(branch):\(filePath)"])
            return output
        } catch let error as GitServiceError {
            if case .executionFailed(let msg) = error,
               msg.contains("does not exist") || msg.contains("not exist") || msg.contains("fatal: path") {
                throw GitServiceError.fileNotFound(branch: branch, path: filePath)
            }
            throw error
        }
    }

    func diffFile(at repoPath: URL, fromRef: String, toRef: String, filePath: String) async throws -> String {
        try await ensureGitRepo(at: repoPath)
        let output = try await runGit(at: repoPath, arguments: ["diff", fromRef, toRef, "--", filePath])
        return output
    }

    // MARK: - Private

    private func ensureGitRepo(at path: URL) async throws {
        let isRepo = try await isGitRepository(at: path)
        if !isRepo {
            throw GitServiceError.notARepository
        }
    }

    private func runGit(at repoPath: URL, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = gitPath
        process.arguments = arguments
        process.currentDirectoryURL = repoPath

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw GitServiceError.executionFailed(message: "Failed to launch git: \(error.localizedDescription)")
        }

        outputPipe.fileHandleForWriting.closeFile()
        errorPipe.fileHandleForWriting.closeFile()

        let result = try await readWithTimeout(outputPipe: outputPipe, errorPipe: errorPipe, process: process)

        if result.didTimeout {
            throw GitServiceError.timeout
        }

        let stderrString = String(data: result.stderr, encoding: .utf8) ?? ""
        if !result.stdout.isEmpty || stderrString.isEmpty {
            return String(data: result.stdout, encoding: .utf8) ?? ""
        }

        if stderrString.contains("fatal:") {
            throw GitServiceError.executionFailed(message: stderrString.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return String(data: result.stdout, encoding: .utf8) ?? ""
    }

    private struct ReadResult {
        let stdout: Data
        let stderr: Data
        let didTimeout: Bool
    }

    private func readWithTimeout(outputPipe: Pipe, errorPipe: Pipe, process: Process) async throws -> ReadResult {
        let timeoutNs = timeoutSeconds * 1_000_000_000
        var stdout = Data()
        var stderr = Data()
        var didTimeout = false

        do {
            try await withThrowingTaskGroup(of: (Data, Data).self) { group in
                group.addTask { @Sendable in
                    let out = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let err = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    return (out, err)
                }
                group.addTask { @Sendable [timeoutNs] in
                    try await Task.sleep(nanoseconds: timeoutNs)
                    throw GitServiceError.timeout
                }

                if let result = try await group.next() {
                    stdout = result.0
                    stderr = result.1
                }
                group.cancelAll()
            }
        } catch is GitServiceError {
            process.terminate()
            didTimeout = true
        }

        return ReadResult(stdout: stdout, stderr: stderr, didTimeout: didTimeout)
    }
}
