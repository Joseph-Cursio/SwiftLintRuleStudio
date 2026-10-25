//
//  ConfigVersionHistoryServiceTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for ConfigVersionHistoryService
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct ConfigVersionHistoryServiceTests {

    // MARK: - Helpers

    private func createTempWorkspace() throws -> (directory: URL, configPath: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VersionHistoryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        return (tempDir, configPath)
    }

    private func cleanup(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A service whose store lives inside the test's own directory, so cleanup removes it.
    @MainActor
    private func makeService(in directory: URL) -> ConfigVersionHistoryService {
        ConfigVersionHistoryService(backups: store(in: directory))
    }

    private func store(in directory: URL) -> ConfigBackupStore {
        ConfigBackupStore(root: directory.appendingPathComponent("store", isDirectory: true))
    }

    /// Writes a backup the way earlier versions did: beside the configuration. These tests
    /// cover that the history still lists, restores, diffs and prunes them.
    private func createBackupFile(
        in directory: URL,
        configName: String,
        timestamp: Int,
        content: String
    ) throws {
        let backupName = "\(configName).\(timestamp).backup"
        let backupPath = directory.appendingPathComponent(backupName)
        try content.write(to: backupPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Tests

    @Test("List backups finds timestamped backup files")
    @MainActor
    func testListBackups() throws {
        let (dir, configPath) = try createTempWorkspace()
        defer { cleanup(dir) }

        try "rules: {}".write(to: configPath, atomically: true, encoding: .utf8)
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1_700_000_000, content: "rules: {}")
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1_700_001_000, content: "rules: {}")
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1_700_002_000, content: "rules: {}")

        let service = makeService(in: dir)
        let backups = service.listBackups(for: configPath)

        try #require(backups.count == 3, "Expected 3 backups")
        // Should be sorted newest first
        #expect(backups[0].timestamp > backups[1].timestamp)
        #expect(backups[1].timestamp > backups[2].timestamp)
    }

    @Test("List backups returns empty for no backups")
    @MainActor
    func testListBackupsEmpty() throws {
        let (dir, configPath) = try createTempWorkspace()
        defer { cleanup(dir) }

        try "rules: {}".write(to: configPath, atomically: true, encoding: .utf8)

        let service = makeService(in: dir)
        let backups = service.listBackups(for: configPath)

        #expect(backups.isEmpty)
    }

    @Test("Parse timestamps from backup filenames")
    @MainActor
    func testParseTimestamps() throws {
        let (dir, configPath) = try createTempWorkspace()
        defer { cleanup(dir) }

        try "rules: {}".write(to: configPath, atomically: true, encoding: .utf8)
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1_700_000_000, content: "rules: {}")

        let service = makeService(in: dir)
        let backups = service.listBackups(for: configPath)

        let backup = try #require(backups.first, "Expected one backup")
        #expect(backup.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Load backup returns content")
    @MainActor
    func testLoadBackup() throws {
        let (dir, configPath) = try createTempWorkspace()
        defer { cleanup(dir) }

        let content = "rules:\n  force_cast: true\n"
        try content.write(to: configPath, atomically: true, encoding: .utf8)
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1_700_000_000, content: content)

        let service = makeService(in: dir)
        let backups = service.listBackups(for: configPath)
        let backup = try #require(backups.first, "Expected backup to load")
        let loaded = try service.loadBackup(backup)

        #expect(loaded == content)
    }

    @Test("Restore backup creates safety backup")
    @MainActor
    func testRestoreCreatesBackup() throws {
        let (dir, configPath) = try createTempWorkspace()
        defer { cleanup(dir) }

        let currentContent = "rules:\n  force_cast: true\n"
        let oldContent = "rules:\n  line_length: true\n"
        try currentContent.write(to: configPath, atomically: true, encoding: .utf8)
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1_700_000_000, content: oldContent)

        let service = makeService(in: dir)
        let backups = service.listBackups(for: configPath)
        let backup = try #require(backups.first, "Expected backup to restore")
        try service.restoreBackup(backup, to: configPath)

        // Check restored content
        let restored = try String(contentsOf: configPath, encoding: .utf8)
        #expect(restored == oldContent)

        // The safety backup goes into the store; the project folder gains nothing.
        let allBackups = service.listBackups(for: configPath)
        #expect(allBackups.count == 2)
        let stored = store(in: dir).storedBackups(for: configPath)
        #expect(stored.count == 1)
        let label = store(in: dir).directory(for: configPath).appendingPathComponent("config-path.txt")
        #expect(FileManager.default.fileExists(atPath: label.path), "a restore labels the folder it creates")
        #expect(try stored.first.map { try String(contentsOf: $0.path, encoding: .utf8) } == currentContent)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
            == [".swiftlint.yml", ".swiftlint.yml.1700000000.backup", "store"])
    }

    @Test("Prune old backups keeps specified count")
    @MainActor
    func testPruneOldBackups() throws {
        let (dir, configPath) = try createTempWorkspace()
        defer { cleanup(dir) }

        try "rules: {}".write(to: configPath, atomically: true, encoding: .utf8)
        for idx in 0..<5 {
            try createBackupFile(
                in: dir,
                configName: ".swiftlint.yml",
                timestamp: 1_700_000_000 + (idx * 1_000),
                content: "rules: {}"
            )
        }

        // And two in the store, the newest of all.
        let store = store(in: dir)
        for (offset, content) in ["store one", "store two"].enumerated() {
            try content.write(to: configPath, atomically: true, encoding: .utf8)
            try store.backUp(configPath, at: Date(timeIntervalSince1970: TimeInterval(1_800_000_000 + offset)))
        }

        let service = makeService(in: dir)
        var backups = service.listBackups(for: configPath)
        #expect(backups.count == 7)

        try service.pruneOldBackups(for: configPath, keepCount: 3)

        backups = service.listBackups(for: configPath)
        let stamps = backups.map { Int($0.timestamp.timeIntervalSince1970) }
        #expect(stamps == [1_800_000_001, 1_800_000_000, 1_700_004_000])
    }

    @Test("Moving earlier backups out goes through the service's discard")
    @MainActor
    func testMoveLegacyBackups() throws {
        let (dir, configPath) = try createTempWorkspace()
        defer { cleanup(dir) }

        try "rules: {}".write(to: configPath, atomically: true, encoding: .utf8)
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1_700_000_000, content: "old")
        let service = ConfigVersionHistoryService(backups: store(in: dir)) {
            try FileManager.default.removeItem(at: $0)
        }

        #expect(service.legacyBackupCount(for: configPath) == 1)
        #expect(try service.moveLegacyBackups(for: configPath) == 1)
        #expect(service.legacyBackupCount(for: configPath) == 0)
        #expect(service.listBackups(for: configPath).count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == [".swiftlint.yml", "store"])
    }

    @Test("Diff between two backups")
    @MainActor
    func testDiffBetweenBackups() throws {
        let (dir, configPath) = try createTempWorkspace()
        defer { cleanup(dir) }

        let content1 = "rules:\n  force_cast: true\n"
        let content2 = "rules:\n  force_cast: true\n  line_length: true\n"
        try content1.write(to: configPath, atomically: true, encoding: .utf8)
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1_700_000_000, content: content1)
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1_700_001_000, content: content2)

        let service = makeService(in: dir)
        let backups = service.listBackups(for: configPath)
        try #require(backups.count == 2, "Expected 2 backups for diff comparison")

        let diff = try service.diffBetween(backups[1], backups[0])
        #expect(diff.hasChanges)
        #expect(diff.addedRules.contains("line_length"))
    }
}
