//
//  GitBranchDiffServiceTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for GitBranchDiffService
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

@MainActor
struct GitBranchDiffServiceTests {

    // MARK: - Helpers

    private func createTempGitRepo(initialConfig: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitBranchDiffTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let git = "/usr/bin/git"
        try shellExec(git, args: ["init"], at: tempDir)
        try shellExec(git, args: ["config", "user.email", "test@test.com"], at: tempDir)
        try shellExec(git, args: ["config", "user.name", "Test"], at: tempDir)

        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        try initialConfig.write(to: configPath, atomically: true, encoding: .utf8)
        try shellExec(git, args: ["add", "."], at: tempDir)
        try shellExec(git, args: ["commit", "-m", "Initial commit"], at: tempDir)

        return tempDir
    }

    private func createBranch(at repoDir: URL, name: String, config: String) throws {
        let git = "/usr/bin/git"
        try shellExec(git, args: ["checkout", "-b", name], at: repoDir)
        let configPath = repoDir.appendingPathComponent(".swiftlint.yml")
        try config.write(to: configPath, atomically: true, encoding: .utf8)
        try shellExec(git, args: ["add", "."], at: repoDir)
        try shellExec(git, args: ["commit", "-m", "Config on \(name)"], at: repoDir)
        try shellExec(git, args: ["checkout", "-"], at: repoDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @discardableResult
    private func shellExec(_ executable: String, args: [String], at directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Tests

    @Test("Lists available refs in repo")
    func testListRefs() async throws {
        let repoDir = try createTempGitRepo(
            initialConfig: "disabled_rules:\n  - trailing_whitespace\n"
        )
        defer { cleanup(repoDir) }
        try createBranch(at: repoDir, name: "feature-a", config: "disabled_rules:\n  - line_length\n")

        let service = GitBranchDiffService(gitService: GitService())
        let refs = try await service.listAvailableRefs(at: repoDir)

        #expect(!refs.currentBranch.isEmpty)
        #expect(refs.branches.contains("feature-a"))
    }

    @Test("Compares config between branches")
    func testCompareConfigBetweenBranches() async throws {
        let mainConfig = "rules:\n  force_cast: true\n"
        let branchConfig = "rules:\n  line_length: true\n"

        let repoDir = try createTempGitRepo(initialConfig: mainConfig)
        defer { cleanup(repoDir) }
        try createBranch(at: repoDir, name: "other-branch", config: branchConfig)

        let service = GitBranchDiffService(
            gitService: GitService(),
            comparisonService: ConfigComparisonService()
        )
        let result = try await service.compareConfigWithBranch(
            repoPath: repoDir,
            branch: "other-branch",
            configRelativePath: ".swiftlint.yml"
        )

        #expect(result.totalDifferences > 0)
        #expect(result.onlyInFirst.contains("force_cast"))
        #expect(result.onlyInSecond.contains("line_length"))
    }

    @Test("Identical configs on different branches show no differences")
    func testIdenticalBranchConfigs() async throws {
        let config = "rules:\n  force_cast: true\n"
        let repoDir = try createTempGitRepo(initialConfig: config)
        defer { cleanup(repoDir) }
        try createBranch(at: repoDir, name: "same-config", config: config)

        let service = GitBranchDiffService(
            gitService: GitService(),
            comparisonService: ConfigComparisonService()
        )
        let result = try await service.compareConfigWithBranch(
            repoPath: repoDir,
            branch: "same-config",
            configRelativePath: ".swiftlint.yml"
        )

        #expect(result.totalDifferences == 0)
    }

    @Test("Non-git repo throws error")
    func testNonGitRepoThrows() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitBranchDiffTests-nonrepo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { cleanup(tempDir) }

        let service = GitBranchDiffService(gitService: GitService())
        await #expect(throws: GitBranchDiffError.self) {
            _ = try await service.listAvailableRefs(at: tempDir)
        }
    }
}
