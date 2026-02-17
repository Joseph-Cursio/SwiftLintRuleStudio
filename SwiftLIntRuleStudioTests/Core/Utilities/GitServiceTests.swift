//
//  GitServiceTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for GitService
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

@MainActor
struct GitServiceTests {

    // MARK: - Helpers

    private func createTempGitRepo() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let git = "/usr/bin/git"
        try shellExec(git, args: ["init"], at: tempDir)
        try shellExec(git, args: ["config", "user.email", "test@test.com"], at: tempDir)
        try shellExec(git, args: ["config", "user.name", "Test"], at: tempDir)

        let configContent = "disabled_rules:\n  - trailing_whitespace\n"
        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        try configContent.write(to: configPath, atomically: true, encoding: .utf8)
        try shellExec(git, args: ["add", "."], at: tempDir)
        try shellExec(git, args: ["commit", "-m", "Initial commit"], at: tempDir)

        return tempDir
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

    @Test("Detects git repository")
    func testIsGitRepository() async throws {
        let repoDir = try createTempGitRepo()
        defer { cleanup(repoDir) }

        let service = GitService()
        let isRepo = try await service.isGitRepository(at: repoDir)
        #expect(isRepo)
    }

    @Test("Non-repo directory returns false")
    func testNonRepoDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitServiceTests-nonrepo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { cleanup(tempDir) }

        let service = GitService()
        let isRepo = try await service.isGitRepository(at: tempDir)
        #expect(!isRepo)
    }

    @Test("Gets current branch")
    func testGetCurrentBranch() async throws {
        let repoDir = try createTempGitRepo()
        defer { cleanup(repoDir) }

        let service = GitService()
        let branch = try await service.getCurrentBranch(at: repoDir)
        #expect(!branch.isEmpty)
    }

    @Test("Lists branches")
    func testListBranches() async throws {
        let repoDir = try createTempGitRepo()
        defer { cleanup(repoDir) }

        try shellExec("/usr/bin/git", args: ["checkout", "-b", "feature-test"], at: repoDir)
        try shellExec("/usr/bin/git", args: ["checkout", "-"], at: repoDir)

        let service = GitService()
        let branches = try await service.listBranches(at: repoDir)
        #expect(branches.count >= 2)
        #expect(branches.contains("feature-test"))
    }

    @Test("Lists tags")
    func testListTags() async throws {
        let repoDir = try createTempGitRepo()
        defer { cleanup(repoDir) }

        try shellExec("/usr/bin/git", args: ["tag", "v1.0.0"], at: repoDir)

        let service = GitService()
        let tags = try await service.listTags(at: repoDir)
        #expect(tags.contains("v1.0.0"))
    }

    @Test("Shows file from branch")
    func testShowFile() async throws {
        let repoDir = try createTempGitRepo()
        defer { cleanup(repoDir) }

        let currentBranch = try shellExec("/usr/bin/git", args: ["rev-parse", "--abbrev-ref", "HEAD"], at: repoDir)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let service = GitService()
        let content = try await service.showFile(at: repoDir, branch: currentBranch, filePath: ".swiftlint.yml")
        #expect(content.contains("trailing_whitespace"))
    }

    @Test("Show file from different branch")
    func testShowFileFromDifferentBranch() async throws {
        let repoDir = try createTempGitRepo()
        defer { cleanup(repoDir) }

        try shellExec("/usr/bin/git", args: ["checkout", "-b", "other-config"], at: repoDir)
        let newConfig = "disabled_rules:\n  - line_length\n"
        try newConfig.write(
            to: repoDir.appendingPathComponent(".swiftlint.yml"),
            atomically: true, encoding: .utf8
        )
        try shellExec("/usr/bin/git", args: ["add", "."], at: repoDir)
        try shellExec("/usr/bin/git", args: ["commit", "-m", "Change config"], at: repoDir)
        try shellExec("/usr/bin/git", args: ["checkout", "-"], at: repoDir)

        let service = GitService()
        let content = try await service.showFile(at: repoDir, branch: "other-config", filePath: ".swiftlint.yml")
        #expect(content.contains("line_length"))
    }

    @Test("Diff file between branches")
    func testDiffFile() async throws {
        let repoDir = try createTempGitRepo()
        defer { cleanup(repoDir) }

        let currentBranch = try shellExec("/usr/bin/git", args: ["rev-parse", "--abbrev-ref", "HEAD"], at: repoDir)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try shellExec("/usr/bin/git", args: ["checkout", "-b", "diff-branch"], at: repoDir)
        let newConfig = "disabled_rules:\n  - line_length\n"
        try newConfig.write(
            to: repoDir.appendingPathComponent(".swiftlint.yml"),
            atomically: true, encoding: .utf8
        )
        try shellExec("/usr/bin/git", args: ["add", "."], at: repoDir)
        try shellExec("/usr/bin/git", args: ["commit", "-m", "Change config"], at: repoDir)

        let service = GitService()
        let diff = try await service.diffFile(
            at: repoDir, fromRef: currentBranch, toRef: "diff-branch", filePath: ".swiftlint.yml"
        )
        #expect(!diff.isEmpty)
    }

    @Test("Not a repository throws error")
    func testNotARepositoryThrows() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitServiceTests-notrepo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { cleanup(tempDir) }

        let service = GitService()
        await #expect(throws: GitServiceError.self) {
            _ = try await service.getCurrentBranch(at: tempDir)
        }
    }
}
