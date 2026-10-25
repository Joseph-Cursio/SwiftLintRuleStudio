//
//  ConfigVersionHistoryViewModelCurrentTests.swift
//  SwiftLintRuleStudioTests
//
//  Comparing a backup with the current configuration, and swapping a comparison.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct ConfigVersionHistoryViewModelCurrentTests {
    private static let configPath = URL(fileURLWithPath: "/tmp/.swiftlint.yml")

    private func makeBackup(timestamp: Date) -> ConfigBackup {
        let path = URL(fileURLWithPath: "/tmp/.swiftlint.yml.\(Int(timestamp.timeIntervalSince1970)).backup")
        return ConfigBackup(id: path.lastPathComponent, path: path, timestamp: timestamp, fileSize: 512)
    }

    /// A real `.swiftlint.yml`, so the view model can list it as the current configuration.
    private func makeConfigFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigVersionHistoryViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(".swiftlint.yml")
        try "opt_in_rules:\n  - empty_count\n".write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    @Test("The current configuration is listed alongside the backups")
    func testListsCurrentConfiguration() throws {
        let file = try makeConfigFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let viewModel = ConfigVersionHistoryViewModel(service: SpyVersionHistoryService(), configPath: file)

        viewModel.loadBackups()

        let current = try #require(viewModel.current)
        #expect(current.path == file)
        #expect(viewModel.isCurrent(current))
        #expect(viewModel.label(for: current) == "Current")
    }

    @Test("Without a config file there's no current entry")
    func testNoCurrentWithoutFile() {
        let viewModel = ConfigVersionHistoryViewModel(service: SpyVersionHistoryService(), configPath: Self.configPath)
        viewModel.loadBackups()
        #expect(viewModel.current == nil)
    }

    @Test("Comparing a backup with the current configuration puts the current one first")
    func testCurrentGoesFirst() throws {
        let file = try makeConfigFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let backup = makeBackup(timestamp: Date(timeIntervalSince1970: 1_000))
        let service = SpyVersionHistoryService(backups: [backup])
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: file)
        viewModel.loadBackups()
        let current = try #require(viewModel.current)

        viewModel.selectForComparison(backup)
        viewModel.selectForComparison(current)

        #expect(viewModel.selectedBackup?.id == current.id)
        #expect(viewModel.comparisonBackup?.id == backup.id)
        #expect(service.diffCalls.last?.before == current.id)
        #expect(viewModel.restoreLabel == "Restore Older Version", "restoring brings back the backup")
    }

    @Test("Swapping reverses the comparison, the diff and what a restore brings back")
    func testSwap() {
        let older = makeBackup(timestamp: Date(timeIntervalSince1970: 1_000))
        let newer = makeBackup(timestamp: Date(timeIntervalSince1970: 2_000))
        let service = SpyVersionHistoryService(backups: [older, newer])
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)
        viewModel.selectForComparison(newer)
        viewModel.selectForComparison(older)
        #expect(viewModel.restoreLabel == "Restore Newer Version")

        viewModel.swapComparison()

        #expect(viewModel.selectedBackup?.id == newer.id)
        #expect(viewModel.comparisonBackup?.id == older.id)
        #expect(service.diffCalls.last?.before == newer.id && service.diffCalls.last?.after == older.id)
        #expect(viewModel.restoreLabel == "Restore Older Version")

        #expect(viewModel.comparisonBackup?.id == older.id, "the version a restore brings back")
    }

    @Test("With the current configuration on the after side there's nothing to restore")
    func testNoRestoreOfCurrent() throws {
        let file = try makeConfigFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let backup = makeBackup(timestamp: Date(timeIntervalSince1970: 1_000))
        let viewModel = ConfigVersionHistoryViewModel(
            service: SpyVersionHistoryService(backups: [backup]),
            configPath: file
        )
        viewModel.loadBackups()
        viewModel.selectForComparison(try #require(viewModel.current))
        viewModel.selectForComparison(backup)

        viewModel.swapComparison()

        #expect(viewModel.restoreLabel == nil)
    }

    @Test("Restoring clears the comparison, which the restore made out of date")
    func testRestoreClearsComparison() {
        let older = makeBackup(timestamp: Date(timeIntervalSince1970: 1_000))
        let newer = makeBackup(timestamp: Date(timeIntervalSince1970: 2_000))
        let viewModel = ConfigVersionHistoryViewModel(
            service: SpyVersionHistoryService(backups: [older, newer]),
            configPath: Self.configPath
        )
        viewModel.selectForComparison(older)
        viewModel.selectForComparison(newer)
        viewModel.confirmRestore(newer)

        viewModel.restoreVersion()

        #expect(viewModel.selectedBackup == nil && viewModel.comparisonBackup == nil && viewModel.currentDiff == nil)
    }

    @Test("Refreshing re-reads a current configuration that's part of the comparison")
    func testRefreshUpdatesCurrent() throws {
        let file = try makeConfigFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let backup = makeBackup(timestamp: Date(timeIntervalSince1970: 1_000))
        let service = SpyVersionHistoryService(backups: [backup])
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: file)
        viewModel.loadBackups()
        viewModel.selectForComparison(try #require(viewModel.current))
        viewModel.selectForComparison(backup)
        let diffsBefore = service.diffCalls.count

        try "opt_in_rules:\n  - empty_count\n  - array_init\n".write(to: file, atomically: true, encoding: .utf8)
        viewModel.loadBackups()

        #expect(service.diffCalls.count == diffsBefore + 1, "the diff is worked out again")
        #expect(viewModel.selectedBackup?.fileSize == viewModel.current?.fileSize)
    }

    @Test("A comparison that can't be worked out again on refresh is cleared, not left showing the old file")
    func testFailedRefreshClearsComparison() throws {
        let file = try makeConfigFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let backup = makeBackup(timestamp: Date(timeIntervalSince1970: 1_000))
        let service = SpyVersionHistoryService(backups: [backup])
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: file)
        viewModel.loadBackups()
        viewModel.selectForComparison(try #require(viewModel.current))
        viewModel.selectForComparison(backup)
        #expect(viewModel.currentDiff != nil)

        // Say the file was saved with a syntax error.
        service.shouldThrowOnDiff = true
        viewModel.loadBackups()

        #expect(viewModel.currentDiff == nil)
        #expect(viewModel.selectedBackup == nil && viewModel.comparisonBackup == nil)
        #expect(viewModel.error != nil)
    }

    @Test("Pruning a backup that's part of the comparison clears it")
    func testPruneClearsComparison() {
        let older = makeBackup(timestamp: Date(timeIntervalSince1970: 1_000))
        let newer = makeBackup(timestamp: Date(timeIntervalSince1970: 2_000))
        let service = SpyVersionHistoryService(backups: [older, newer])
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)
        viewModel.loadBackups()
        viewModel.selectForComparison(older)
        viewModel.selectForComparison(newer)

        service.backupsToReturn = [newer]
        viewModel.loadBackups()

        #expect(viewModel.selectedBackup == nil && viewModel.comparisonBackup == nil)
    }

    @Test("A swap that can't be worked out leaves the comparison as it was")
    func testFailedSwapChangesNothing() {
        let older = makeBackup(timestamp: Date(timeIntervalSince1970: 1_000))
        let newer = makeBackup(timestamp: Date(timeIntervalSince1970: 2_000))
        let service = SpyVersionHistoryService(backups: [older, newer])
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)
        viewModel.selectForComparison(older)
        viewModel.selectForComparison(newer)

        service.shouldThrowOnDiff = true
        viewModel.swapComparison()

        #expect(viewModel.selectedBackup?.id == older.id && viewModel.comparisonBackup?.id == newer.id)
        #expect(viewModel.error != nil)
    }

    @Test("Restoring a backup over the current configuration is restoring the older version, whatever the dates")
    func testRestoreOverCurrentIsOlder() throws {
        let file = try makeConfigFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        // A file copied in keeps its old date, so a backup can look newer than it.
        let backup = makeBackup(timestamp: Date.now.addingTimeInterval(86_400))
        let viewModel = ConfigVersionHistoryViewModel(
            service: SpyVersionHistoryService(backups: [backup]),
            configPath: file
        )
        viewModel.loadBackups()
        viewModel.selectForComparison(backup)
        viewModel.selectForComparison(try #require(viewModel.current))

        #expect(viewModel.restoreLabel == "Restore Older Version")
    }

    @Test("Clicking the selected version again deselects it instead of comparing it with itself")
    func testSecondClickDeselects() {
        let backup = makeBackup(timestamp: Date(timeIntervalSince1970: 1_000))
        let viewModel = ConfigVersionHistoryViewModel(
            service: SpyVersionHistoryService(backups: [backup]),
            configPath: Self.configPath
        )

        viewModel.selectForComparison(backup)
        viewModel.selectForComparison(backup)

        #expect(viewModel.selectedBackup == nil && viewModel.comparisonBackup == nil)
        #expect(viewModel.restoreLabel == nil)
    }
}
