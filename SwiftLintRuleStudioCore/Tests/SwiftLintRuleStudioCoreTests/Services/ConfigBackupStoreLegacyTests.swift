//
//  ConfigBackupStoreLegacyTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Backups earlier versions left in the user's project folder, one per save (issue #83): moving
//  them into the store on request without losing any, and saves that no longer add to them.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct ConfigBackupStoreLegacyTests {

    private struct Fixture {
        let project: URL
        let config: URL
        let store: ConfigBackupStore
    }

    private struct DiscardError: Error {}

    private func makeFixture(retention: Int = 50) throws -> Fixture {
        let base = TestTempDirectory.make("backup-legacy")
        let project = base.appendingPathComponent("MyProject", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let config = project.appendingPathComponent(".swiftlint.yml")
        try "rules: {}\n".write(to: config, atomically: true, encoding: .utf8)
        let store = ConfigBackupStore(
            root: base.appendingPathComponent("store", isDirectory: true),
            retention: retention
        )
        return Fixture(project: project, config: config, store: store)
    }

    private func writeLegacy(_ seconds: Int, _ content: String, in fixture: Fixture) throws {
        try content.write(
            to: fixture.project.appendingPathComponent(".swiftlint.yml.\(seconds).backup"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func projectFiles(_ fixture: Fixture) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: fixture.project.path).sorted()
    }

    /// Deletes rather than trashes, so a test run doesn't fill the developer's Trash.
    private let delete: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }

    // MARK: - Moving in

    @Test("moving earlier backups in leaves the project folder with only the configuration")
    func moveEmptiesTheProjectFolder() throws {
        let fixture = try makeFixture()
        try writeLegacy(1_700_000_000, "one\n", in: fixture)
        try writeLegacy(1_700_000_100, "two\n", in: fixture)

        let moved = try fixture.store.moveLegacyBackups(of: fixture.config, discard: delete)

        #expect(moved == 2)
        #expect(try projectFiles(fixture) == [".swiftlint.yml"])
        // Into `Earlier`, apart from the store's own backups, so retention never reaches them.
        #expect(fixture.store.storedBackups(for: fixture.config).isEmpty)
        let stored = fixture.store.earlierBackups(for: fixture.config)
        #expect(stored.map(\.timestamp) == [
            Date(timeIntervalSince1970: 1_700_000_100),
            Date(timeIntervalSince1970: 1_700_000_000)
        ])
        #expect(try stored.map { try String(contentsOf: $0.path, encoding: .utf8) } == ["two\n", "one\n"])
    }

    @Test("a backup already moved in under its name just leaves the project")
    func identicalBackupIsOnlyDiscarded() throws {
        let fixture = try makeFixture()
        try writeLegacy(1_700_000_000, "same\n", in: fixture)
        let folder = fixture.store.earlierDirectory(for: fixture.config)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "same\n".write(
            to: folder.appendingPathComponent(".swiftlint.yml.1700000000.backup"),
            atomically: true,
            encoding: .utf8
        )

        #expect(try fixture.store.moveLegacyBackups(of: fixture.config, discard: delete) == 1)
        #expect(fixture.store.earlierBackups(for: fixture.config).count == 1)
        #expect(try projectFiles(fixture) == [".swiftlint.yml"])
    }

    @Test("a backup whose name is taken by different contents moves in a second later, oldest first")
    func clashingNameKeepsBoth() throws {
        let fixture = try makeFixture()
        try writeLegacy(1_700_000_000, "from the project\n", in: fixture)
        try writeLegacy(1_700_000_002, "newer\n", in: fixture)
        let folder = fixture.store.earlierDirectory(for: fixture.config)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "from the store\n".write(
            to: folder.appendingPathComponent(".swiftlint.yml.1700000000.backup"),
            atomically: true,
            encoding: .utf8
        )

        try fixture.store.moveLegacyBackups(of: fixture.config, discard: delete)

        let moved = folder.appendingPathComponent(".swiftlint.yml.1700000001.backup")
        #expect(try String(contentsOf: moved, encoding: .utf8) == "from the project\n")
        // The newer backup keeps its own second, so it still lists as the newest.
        let listed = try fixture.store.earlierBackups(for: fixture.config)
            .map { try String(contentsOf: $0.path, encoding: .utf8) }
        #expect(listed == ["newer\n", "from the project\n", "from the store\n"])
    }

    @Test("a backup that can't be copied in is never discarded")
    func failedCopyDiscardsNothing() throws {
        let fixture = try makeFixture()
        try writeLegacy(1_700_000_000, "keep me\n", in: fixture)
        let folder = fixture.store.earlierDirectory(for: fixture.config)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        let moved = try fixture.store.moveLegacyBackups(of: fixture.config, discard: delete)

        #expect(moved == 0)
        #expect(try projectFiles(fixture) == [".swiftlint.yml", ".swiftlint.yml.1700000000.backup"])
    }

    @Test("a backup that can't leave the project stays there, and isn't duplicated into the store")
    func failedDiscardLosesNothing() throws {
        let fixture = try makeFixture()
        try writeLegacy(1_700_000_000, "stuck\n", in: fixture)

        let moved = try fixture.store.moveLegacyBackups(of: fixture.config) { _ in throw DiscardError() }

        #expect(moved == 0)
        #expect(try projectFiles(fixture) == [".swiftlint.yml", ".swiftlint.yml.1700000000.backup"])
        #expect(fixture.store.earlierBackups(for: fixture.config).isEmpty)
        #expect(fixture.store.backups(for: fixture.config).count == 1)
    }

    @Test("a backup someone made by hand is not the app's, so it stays")
    func handMadeBackupsAreLeftAlone() throws {
        let fixture = try makeFixture()
        try "mine\n".write(
            to: fixture.project.appendingPathComponent(".swiftlint.yml.20240115.backup"),
            atomically: true,
            encoding: .utf8
        )

        #expect(try fixture.store.moveLegacyBackups(of: fixture.config, discard: delete) == 0)
        #expect(try projectFiles(fixture) == [".swiftlint.yml", ".swiftlint.yml.20240115.backup"])
    }

    // MARK: - Saving

    @Test("saving never moves or deletes earlier backups in the project folder, even past retention")
    func savingLeavesEarlierBackupsAlone() throws {
        let fixture = try makeFixture(retention: 2)
        for second in 0..<4 {
            try writeLegacy(1_600_000_000 + second, "old \(second)\n", in: fixture)
        }

        for version in 0..<3 {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.disabledRules = ["rule_\(version)"]
            try YAMLConfigurationEngine.save(config, to: fixture.config, backups: fixture.store)
        }

        #expect(try projectFiles(fixture).count == 5, "the configuration and its four earlier backups")
        #expect(fixture.store.storedBackups(for: fixture.config).count == 2)
    }

    @Test("backups moved in from the project are never pruned by later saves")
    func movedBackupsSurviveRetention() throws {
        let fixture = try makeFixture(retention: 2)
        for second in 0..<5 {
            try writeLegacy(1_600_000_000 + second, "old \(second)\n", in: fixture)
        }
        #expect(try fixture.store.moveLegacyBackups(of: fixture.config, discard: delete) == 5)

        for version in 0..<3 {
            var config = YAMLConfigurationEngine.YAMLConfig()
            config.disabledRules = ["rule_\(version)"]
            try YAMLConfigurationEngine.save(config, to: fixture.config, backups: fixture.store)
        }

        #expect(fixture.store.earlierBackups(for: fixture.config).count == 5)
        #expect(fixture.store.storedBackups(for: fixture.config).count == 2)
    }

    @Test("a save whose write fails costs no history")
    func failedWriteDoesNotPrune() throws {
        let fixture = try makeFixture(retention: 2)
        for second in 0..<2 {
            try "version \(second)\n".write(to: fixture.config, atomically: true, encoding: .utf8)
            let date = Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + second))
            try fixture.store.backUp(fixture.config, at: date)
        }
        try "current\n".write(to: fixture.config, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.project.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.project.path) }

        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["todo"]
        #expect(throws: (any Error).self) {
            try YAMLConfigurationEngine.save(config, to: fixture.config, backups: fixture.store)
        }

        // Both earlier versions survive alongside the backup of "current" the save took first.
        let stored = try fixture.store.storedBackups(for: fixture.config)
            .map { try String(contentsOf: $0.path, encoding: .utf8) }
        #expect(stored.count == 3)
        #expect(stored.contains("version 0\n") && stored.contains("version 1\n"))
    }
}
