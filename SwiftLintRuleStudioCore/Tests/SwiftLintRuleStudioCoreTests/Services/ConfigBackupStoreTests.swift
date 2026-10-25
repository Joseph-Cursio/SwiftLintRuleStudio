//
//  ConfigBackupStoreTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Where configuration backups live — the app's own folder, not the user's project — and the
//  rules that keep a backup from being lost: what gets copied, when it is skipped, and what
//  retention may delete. Moving earlier backups in is in ConfigBackupStoreLegacyTests.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct ConfigBackupStoreTests {

    private struct Fixture {
        let project: URL
        let config: URL
        let store: ConfigBackupStore
    }

    private func makeFixture(content: String? = "rules: {}\n", retention: Int = 50) throws -> Fixture {
        let base = TestTempDirectory.make("backup-store")
        let project = base.appendingPathComponent("MyProject", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let config = project.appendingPathComponent(".swiftlint.yml")
        if let content {
            try content.write(to: config, atomically: true, encoding: .utf8)
        }
        let store = ConfigBackupStore(
            root: base.appendingPathComponent("store", isDirectory: true),
            retention: retention
        )
        return Fixture(project: project, config: config, store: store)
    }

    private func at(_ seconds: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private func text(_ url: URL?) throws -> String? {
        try url.map { try String(contentsOf: $0, encoding: .utf8) }
    }

    // MARK: - Location

    @Test("a test run never writes into the real Application Support")
    func standardStoreIsTemporaryInTests() {
        let root = ConfigBackupStore.standard.root.path
        #expect(root.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(!root.contains("/Library/Application Support/"))
    }

    @Test("a configuration's folder doesn't move when the file is deleted, or spelled through /private")
    func directoryIsStable() throws {
        let fixture = try makeFixture()
        let before = fixture.store.directory(for: fixture.config)
        try FileManager.default.removeItem(at: fixture.config)
        #expect(fixture.store.directory(for: fixture.config) == before)

        let privateSpelling = URL(fileURLWithPath: "/private" + fixture.config.path)
        if fixture.config.path.hasPrefix("/var/") {
            #expect(fixture.store.directory(for: privateSpelling) == before)
        }
    }

    @Test("a project opened through a symlinked folder finds the same history")
    func symlinkedProjectFolderSharesTheHistory() throws {
        let fixture = try makeFixture()
        let link = fixture.project.deletingLastPathComponent().appendingPathComponent("current")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.project)
        let throughLink = link.appendingPathComponent(".swiftlint.yml")
        #expect(fixture.store.directory(for: throughLink) == fixture.store.directory(for: fixture.config))
    }

    @Test("two configurations in one folder keep separate histories, named after the project")
    func directoryPerConfiguration() throws {
        let fixture = try makeFixture()
        let other = fixture.project.appendingPathComponent("strict.yml")
        let folder = fixture.store.directory(for: fixture.config)
        #expect(folder != fixture.store.directory(for: other))
        #expect(folder.lastPathComponent.hasPrefix("MyProject-"))
        #expect(folder.deletingLastPathComponent() == fixture.store.root)
    }

    @Test("a very long project name still makes a folder name the file system accepts")
    func longProjectNamesAreShortened() {
        let store = ConfigBackupStore(root: URL(fileURLWithPath: "/store"))
        let project = String(repeating: "設定", count: 120)
        let folder = store.directory(for: URL(fileURLWithPath: "/work/\(project)/.swiftlint.yml"))
        #expect(folder.lastPathComponent.utf8.count <= 255)
    }

    // MARK: - Taking a backup

    @Test("a backup holds the file's contents, in the store, and the project folder gains nothing")
    func backUpCopiesIntoTheStore() throws {
        let fixture = try makeFixture(content: "opt_in_rules:\n  - empty_count\n")
        let backup = try #require(try fixture.store.backUp(fixture.config, at: at(1_700_000_000)))

        #expect(backup.deletingLastPathComponent() == fixture.store.directory(for: fixture.config))
        #expect(backup.lastPathComponent == ".swiftlint.yml.1700000000.backup")
        #expect(try text(backup) == "opt_in_rules:\n  - empty_count\n")
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.project.path) == [".swiftlint.yml"])
        let label = fixture.store.directory(for: fixture.config).appendingPathComponent("config-path.txt")
        #expect(try text(label)?.contains("MyProject/.swiftlint.yml") == true)
    }

    @Test("a backup taken at t is listed at t")
    func timestampRoundTrips() throws {
        let fixture = try makeFixture()
        try fixture.store.backUp(fixture.config, at: at(1_712_345_678))
        #expect(fixture.store.backups(for: fixture.config).map(\.timestamp) == [at(1_712_345_678)])
    }

    @Test("nothing to back up creates nothing")
    func missingConfigMakesNoBackup() throws {
        let fixture = try makeFixture(content: nil)
        #expect(try fixture.store.backUp(fixture.config, at: at(1_700_000_000)) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.store.root.path))
    }

    @Test("a file that hasn't changed since the newest backup isn't backed up again")
    func unchangedFileIsSkipped() throws {
        let fixture = try makeFixture(content: "A\n")
        try fixture.store.backUp(fixture.config, at: at(1_700_000_000))
        #expect(try fixture.store.backUp(fixture.config, at: at(1_700_000_100)) == nil)

        // Compared with the newest, not with any: A, B, then A again is a new version.
        try "B\n".write(to: fixture.config, atomically: true, encoding: .utf8)
        #expect(try fixture.store.backUp(fixture.config, at: at(1_700_000_200)) != nil)
        try "A\n".write(to: fixture.config, atomically: true, encoding: .utf8)
        #expect(try fixture.store.backUp(fixture.config, at: at(1_700_000_300)) != nil)
        #expect(try fixture.store.backUp(fixture.config, at: at(1_700_000_400)) == nil)
        #expect(fixture.store.storedBackups(for: fixture.config).count == 3)
    }

    @Test("two backups in one second don't overwrite each other")
    func sameSecondTakesTheNextOne() throws {
        let fixture = try makeFixture(content: "first\n")
        try fixture.store.backUp(fixture.config, at: at(1_700_000_000))
        try "second\n".write(to: fixture.config, atomically: true, encoding: .utf8)
        let later = try fixture.store.backUp(fixture.config, at: at(1_700_000_000))

        #expect(later?.lastPathComponent == ".swiftlint.yml.1700000001.backup")
        let contents = try fixture.store.storedBackups(for: fixture.config).map { try text($0.path) }
        #expect(contents == ["second\n", "first\n"])
    }

    @Test("a symlinked configuration is backed up as its contents, not as a link")
    func symlinkIsCopiedAsBytes() throws {
        let fixture = try makeFixture(content: nil)
        let shared = fixture.project.deletingLastPathComponent().appendingPathComponent("shared.yml")
        try "shared: true\n".write(to: shared, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: fixture.config, withDestinationURL: shared)

        let backup = try #require(try fixture.store.backUp(fixture.config, at: at(1_700_000_000)))
        let type = try FileManager.default.attributesOfItem(atPath: backup.path)[.type] as? FileAttributeType
        #expect(type == .typeRegular)
        #expect(try text(backup) == "shared: true\n")
    }

    // MARK: - Retention

    @Test("retention keeps the newest and the very oldest, and only ever the store's")
    func retentionKeepsTheOldest() throws {
        let fixture = try makeFixture(retention: 3)
        let legacy = fixture.project.appendingPathComponent(".swiftlint.yml.1600000000.backup")
        try "legacy\n".write(to: legacy, atomically: true, encoding: .utf8)
        for second in 0..<6 {
            try "version \(second)\n".write(to: fixture.config, atomically: true, encoding: .utf8)
            try fixture.store.backUp(fixture.config, at: at(1_700_000_000 + second))
        }

        fixture.store.applyRetention(to: fixture.config)

        let kept = fixture.store.storedBackups(for: fixture.config).map(\.timestamp)
        #expect(kept == [at(1_700_000_005), at(1_700_000_004), at(1_700_000_000)])
        #expect(FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test("over the limit, repeated contents go before distinct versions")
    func retentionDropsRepeatsFirst() throws {
        let fixture = try makeFixture(retention: 3)
        for (second, content) in ["v1", "v2", "v3", "v2"].enumerated() {
            try "\(content)\n".write(to: fixture.config, atomically: true, encoding: .utf8)
            try fixture.store.backUp(fixture.config, at: at(1_700_000_000 + second))
        }

        fixture.store.applyRetention(to: fixture.config)

        let kept = try fixture.store.storedBackups(for: fixture.config).map { try text($0.path) }
        #expect(kept == ["v2\n", "v3\n", "v1\n"])
    }

    @Test("a retention below two still keeps the newest backup")
    func retentionFloor() {
        #expect(ConfigBackupStore(root: URL(fileURLWithPath: "/store"), retention: 1).retention == 2)
    }

    // MARK: - Listing

    @Test("the history lists the store's backups and those beside the file, newest first, none hidden")
    func listingMergesBothPlaces() throws {
        let fixture = try makeFixture()
        try fixture.store.backUp(fixture.config, at: at(1_700_000_200))
        for (name, content) in [
            (".swiftlint.yml.1700000100.backup", "legacy\n"),
            (".swiftlint.yml.1700000200.backup", "duplicate name\n")
        ] {
            try content.write(to: fixture.project.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let listed = fixture.store.backups(for: fixture.config)

        // The same name in two places is two backups, with ids of their own.
        #expect(listed.map(\.timestamp) == [at(1_700_000_200), at(1_700_000_200), at(1_700_000_100)])
        #expect(Set(listed.map(\.id)).count == 3)
        // Directory listings spell the temporary folder as /private/var, so compare resolved.
        #expect(listed.first?.path.deletingLastPathComponent().resolvingSymlinksInPath()
            == fixture.store.directory(for: fixture.config).resolvingSymlinksInPath())
    }
}
