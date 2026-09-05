//
//  ConfigVersionHistoryFileIOTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Restore is the operation with consequences: it replaces the user's configuration, and it
//  makes a safety copy first so the replacement is undoable. Everything worth asserting about
//  it is on the failure paths — an unreadable backup, an unwritable config — and those cannot
//  be reached on a real file system without arranging a permission error or a full disk.
//
//  These use an in-memory `FileIO`, which is what the injected seam is for. The happy-path
//  behaviour is already covered elsewhere against real temp directories, and stays there.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@Suite("Config version history — restore under file-system failure")
struct ConfigVersionHistoryFileIOTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let configPath = URL(fileURLWithPath: "/cfg/.swiftlint.yml")
    private static let backupPath = URL(fileURLWithPath: "/cfg/.swiftlint.yml.1699000000.backup")

    private struct IOError: Error {}

    /// A file system in a dictionary. `failingReads` and `failingWrites` name the paths that
    /// throw, which is the whole reason for using this instead of a temp directory.
    /// `nonisolated` because the package defaults to `MainActor` isolation, and these properties
    /// are read from inside the `@Sendable` closures `FileIO` is made of.
    nonisolated private final class FakeDisk: @unchecked Sendable {
        var contents: [URL: String]
        var failingReads: Set<URL> = []
        var failingWrites: Set<URL> = []

        init(_ contents: [URL: String]) { self.contents = contents }

        func io() -> FileIO {
            FileIO(
                read: { [self] url in
                    if failingReads.contains(url) { throw IOError() }
                    guard let text = contents[url] else { throw IOError() }
                    return text
                },
                write: { [self] text, url in
                    if failingWrites.contains(url) { throw IOError() }
                    contents[url] = text
                },
                exists: { [self] url in contents[url] != nil },
                copy: { [self] from, destination in
                    guard let text = contents[from] else { throw IOError() }
                    contents[destination] = text
                }
            )
        }
    }

    private func backup() -> ConfigBackup {
        ConfigBackup(id: "b", path: Self.backupPath, timestamp: Date(timeIntervalSince1970: 1_699_000_000), fileSize: 4)
    }

    // MARK: - The happy path, stated once

    @Test("restoring writes the backup's content over the config")
    func restoreReplacesTheConfig() throws {
        let disk = FakeDisk([Self.configPath: "current", Self.backupPath: "restored"])
        let service = ConfigVersionHistoryService(now: .fixed(Self.instant), files: disk.io())

        try service.restoreBackup(backup(), to: Self.configPath)

        #expect(disk.contents[Self.configPath] == "restored")
    }

    @Test("the safety copy holds what the config said before the restore")
    func safetyBackupHoldsThePreviousConfig() throws {
        // The safety copy exists so the restore is undoable. If it captured the *new* content it
        // would be worthless, and nothing said which it was.
        let disk = FakeDisk([Self.configPath: "current", Self.backupPath: "restored"])
        let service = ConfigVersionHistoryService(now: .fixed(Self.instant), files: disk.io())

        try service.restoreBackup(backup(), to: Self.configPath)

        let safety = Self.configPath.deletingLastPathComponent()
            .appendingPathComponent(".swiftlint.yml.1700000000.backup")
        #expect(disk.contents[safety] == "current")
    }

    // MARK: - The failure paths, which are why the seam exists

    @Test("an unreadable backup leaves the configuration untouched")
    func unreadableBackupDoesNotDestroyTheConfig() {
        let disk = FakeDisk([Self.configPath: "current", Self.backupPath: "restored"])
        disk.failingReads = [Self.backupPath]
        let service = ConfigVersionHistoryService(now: .fixed(Self.instant), files: disk.io())

        #expect(throws: (any Error).self) {
            try service.restoreBackup(backup(), to: Self.configPath)
        }
        #expect(disk.contents[Self.configPath] == "current")
    }

    @Test("an unreadable backup leaves no stray safety copy behind")
    func unreadableBackupLeavesNoSafetyCopy() {
        // This is the behaviour change: the read now happens before the copy. Previously the
        // safety copy was made first, so a restore that then failed to read its backup left a
        // spurious `.backup` file in the user's config directory. The configuration was never at
        // risk either way — the write was always last — but the litter was real.
        let disk = FakeDisk([Self.configPath: "current", Self.backupPath: "restored"])
        disk.failingReads = [Self.backupPath]
        let service = ConfigVersionHistoryService(now: .fixed(Self.instant), files: disk.io())

        try? service.restoreBackup(backup(), to: Self.configPath)

        let safety = Self.configPath.deletingLastPathComponent()
            .appendingPathComponent(".swiftlint.yml.1700000000.backup")
        #expect(disk.contents[safety] == nil)
        #expect(disk.contents.count == 2, "only the config and the backup should remain")
    }

    @Test("a failed write still leaves the safety copy to recover from")
    func failedWriteKeepsTheSafetyCopy() {
        // The other order matters too: if the write fails, the safety copy must already exist,
        // because that is the only record of what the config said.
        let disk = FakeDisk([Self.configPath: "current", Self.backupPath: "restored"])
        disk.failingWrites = [Self.configPath]
        let service = ConfigVersionHistoryService(now: .fixed(Self.instant), files: disk.io())

        #expect(throws: (any Error).self) {
            try service.restoreBackup(backup(), to: Self.configPath)
        }

        let safety = Self.configPath.deletingLastPathComponent()
            .appendingPathComponent(".swiftlint.yml.1700000000.backup")
        #expect(disk.contents[safety] == "current")
    }

    @Test("restoring over a config that does not exist makes no safety copy")
    func absentConfigNeedsNoSafetyCopy() throws {
        let disk = FakeDisk([Self.backupPath: "restored"])
        let service = ConfigVersionHistoryService(now: .fixed(Self.instant), files: disk.io())

        try service.restoreBackup(backup(), to: Self.configPath)

        #expect(disk.contents[Self.configPath] == "restored")
        #expect(disk.contents.count == 2, "no safety copy of a file that was not there")
    }

    // MARK: - loadBackup

    @Test("loading a backup returns its content and propagates a read failure")
    func loadBackupReadsThrough() throws {
        let disk = FakeDisk([Self.backupPath: "stored"])
        let service = ConfigVersionHistoryService(files: disk.io())
        #expect(try service.loadBackup(backup()) == "stored")

        disk.failingReads = [Self.backupPath]
        #expect(throws: (any Error).self) { try service.loadBackup(backup()) }
    }
}
