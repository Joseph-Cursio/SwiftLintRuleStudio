//
//  ConfigVersionHistoryServiceTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for ConfigVersionHistoryService
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

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
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1700000000, content: "rules: {}")
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1700001000, content: "rules: {}")
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1700002000, content: "rules: {}")

        let service = ConfigVersionHistoryService()
        let backups = service.listBackups(for: configPath)

        #expect(backups.count == 3)
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

        let service = ConfigVersionHistoryService()
        let backups = service.listBackups(for: configPath)

        #expect(backups.isEmpty)
    }

    @Test("Parse timestamps from backup filenames")
    @MainActor
    func testParseTimestamps() throws {
        let (dir, configPath) = try createTempWorkspace()
        defer { cleanup(dir) }

        try "rules: {}".write(to: configPath, atomically: true, encoding: .utf8)
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1700000000, content: "rules: {}")

        let service = ConfigVersionHistoryService()
        let backups = service.listBackups(for: configPath)

        #expect(backups.count == 1)
        #expect(backups[0].timestamp == Date(timeIntervalSince1970: 1700000000))
    }

    @Test("Load backup returns content")
    @MainActor
    func testLoadBackup() throws {
        let (dir, configPath) = try createTempWorkspace()
        defer { cleanup(dir) }

        let content = "rules:\n  force_cast: true\n"
        try content.write(to: configPath, atomically: true, encoding: .utf8)
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1700000000, content: content)

        let service = ConfigVersionHistoryService()
        let backups = service.listBackups(for: configPath)
        let loaded = try service.loadBackup(backups[0])

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
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1700000000, content: oldContent)

        let service = ConfigVersionHistoryService()
        let backups = service.listBackups(for: configPath)
        try service.restoreBackup(backups[0], to: configPath)

        // Check restored content
        let restored = try String(contentsOf: configPath, encoding: .utf8)
        #expect(restored == oldContent)

        // Check safety backup was created
        let allBackups = service.listBackups(for: configPath)
        #expect(allBackups.count >= 2)
    }

    @Test("Prune old backups keeps specified count")
    @MainActor
    func testPruneOldBackups() throws {
        let (dir, configPath) = try createTempWorkspace()
        defer { cleanup(dir) }

        try "rules: {}".write(to: configPath, atomically: true, encoding: .utf8)
        for i in 0..<5 {
            try createBackupFile(
                in: dir,
                configName: ".swiftlint.yml",
                timestamp: 1700000000 + (i * 1000),
                content: "rules: {}"
            )
        }

        let service = ConfigVersionHistoryService()
        var backups = service.listBackups(for: configPath)
        #expect(backups.count == 5)

        try service.pruneOldBackups(for: configPath, keepCount: 2)

        backups = service.listBackups(for: configPath)
        #expect(backups.count == 2)
    }

    @Test("Diff between two backups")
    @MainActor
    func testDiffBetweenBackups() throws {
        let (dir, configPath) = try createTempWorkspace()
        defer { cleanup(dir) }

        let content1 = "rules:\n  force_cast: true\n"
        let content2 = "rules:\n  force_cast: true\n  line_length: true\n"
        try content1.write(to: configPath, atomically: true, encoding: .utf8)
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1700000000, content: content1)
        try createBackupFile(in: dir, configName: ".swiftlint.yml", timestamp: 1700001000, content: content2)

        let service = ConfigVersionHistoryService()
        let backups = service.listBackups(for: configPath)

        let diff = try service.diffBetween(backups[1], backups[0])
        #expect(diff.hasChanges)
        #expect(diff.addedRules.contains("line_length"))
    }
}
