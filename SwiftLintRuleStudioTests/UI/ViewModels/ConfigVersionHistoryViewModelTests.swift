//
//  ConfigVersionHistoryViewModelTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for ConfigVersionHistoryViewModel state management and service delegation
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

@MainActor
struct ConfigVersionHistoryViewModelTests {

    // MARK: - Helpers

    private func makeBackup(
        timestamp: Date = Date.now,
        fileSize: Int64 = 512
    ) -> ConfigBackup {
        let path = URL(fileURLWithPath: "/tmp/.swiftlint.yml.\(Int(timestamp.timeIntervalSince1970)).backup")
        return ConfigBackup(
            id: path.lastPathComponent,
            path: path,
            timestamp: timestamp,
            fileSize: fileSize
        )
    }

    private func makeDiff(addedRules: [String] = ["new_rule"]) -> YAMLConfigurationEngine.ConfigDiff {
        YAMLConfigurationEngine.ConfigDiff(
            addedRules: addedRules,
            removedRules: [],
            modifiedRules: [],
            before: "",
            after: ""
        )
    }

    private static let configPath = URL(fileURLWithPath: "/tmp/.swiftlint.yml")

    // MARK: - Initial State

    @Test("Initial state has empty backups and no selection")
    func testInitialState() {
        let service = SpyVersionHistoryService()
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: nil)
        #expect(viewModel.backups.isEmpty)
        #expect(viewModel.selectedBackup == nil)
        #expect(viewModel.comparisonBackup == nil)
        #expect(viewModel.currentDiff == nil)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.showRestoreConfirmation == false)
        #expect(viewModel.backupToRestore == nil)
        #expect(viewModel.error == nil)
    }

    // MARK: - loadBackups

    @Test("loadBackups with nil configPath returns empty list and does not call service")
    func testLoadBackupsNilPath() {
        let service = SpyVersionHistoryService()
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: nil)
        viewModel.loadBackups()
        #expect(viewModel.backups.isEmpty)
        #expect(service.listBackupsCallCount == 0)
    }

    @Test("loadBackups populates backups from service and clears isLoading")
    func testLoadBackupsPopulates() {
        let backup1 = makeBackup(timestamp: Date(timeIntervalSince1970: 1_000))
        let backup2 = makeBackup(timestamp: Date(timeIntervalSince1970: 2_000))
        let service = SpyVersionHistoryService(backups: [backup1, backup2])
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        viewModel.loadBackups()

        #expect(viewModel.backups.count == 2)
        #expect(viewModel.isLoading == false)
        #expect(service.listBackupsCallCount == 1)
    }

    @Test("loadBackups passes the correct configPath to the service")
    func testLoadBackupsPassesCorrectPath() {
        let expectedPath = URL(fileURLWithPath: "/project/.swiftlint.yml")
        let service = SpyVersionHistoryService()
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: expectedPath)

        viewModel.loadBackups()

        #expect(service.lastListBackupsPath == expectedPath)
    }

    // MARK: - selectForComparison state machine

    @Test("First selectForComparison call sets selectedBackup only")
    func testFirstSelectionSetsSelectedBackup() {
        let backup = makeBackup()
        let service = SpyVersionHistoryService(backups: [backup])
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        viewModel.selectForComparison(backup)

        #expect(viewModel.selectedBackup?.id == backup.id)
        #expect(viewModel.comparisonBackup == nil)
        #expect(viewModel.currentDiff == nil)
    }

    @Test("Second selectForComparison call sets comparisonBackup and generates diff")
    func testSecondSelectionGeneratesDiff() {
        let backup1 = makeBackup(timestamp: Date(timeIntervalSince1970: 1_000))
        let backup2 = makeBackup(timestamp: Date(timeIntervalSince1970: 2_000))
        let diff = makeDiff(addedRules: ["force_cast"])
        let service = SpyVersionHistoryService(backups: [backup1, backup2], diffResult: diff)
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        viewModel.selectForComparison(backup1)
        viewModel.selectForComparison(backup2)

        #expect(viewModel.selectedBackup?.id == backup1.id)
        #expect(viewModel.comparisonBackup?.id == backup2.id)
        #expect(viewModel.currentDiff?.addedRules.contains("force_cast") == true)
    }

    @Test("Third selectForComparison call resets selection to the new backup")
    func testThirdSelectionResetsState() {
        let backup1 = makeBackup(timestamp: Date(timeIntervalSince1970: 1_000))
        let backup2 = makeBackup(timestamp: Date(timeIntervalSince1970: 2_000))
        let backup3 = makeBackup(timestamp: Date(timeIntervalSince1970: 3_000))
        let service = SpyVersionHistoryService(backups: [backup1, backup2, backup3])
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        viewModel.selectForComparison(backup1)
        viewModel.selectForComparison(backup2)
        viewModel.selectForComparison(backup3)

        #expect(viewModel.selectedBackup?.id == backup3.id)
        #expect(viewModel.comparisonBackup == nil)
        #expect(viewModel.currentDiff == nil)
    }

    @Test("Diff generation error is stored in error property")
    func testDiffGenerationErrorStoredInError() {
        let backup1 = makeBackup()
        let backup2 = makeBackup()
        let service = SpyVersionHistoryService(shouldThrowOnDiff: true)
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        viewModel.selectForComparison(backup1)
        viewModel.selectForComparison(backup2)

        #expect(viewModel.error != nil)
        #expect(viewModel.currentDiff == nil)
    }

    // MARK: - clearComparison

    @Test("clearComparison resets all selection state to nil")
    func testClearComparison() {
        let backup1 = makeBackup()
        let backup2 = makeBackup()
        let diff = makeDiff()
        let service = SpyVersionHistoryService(diffResult: diff)
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        viewModel.selectForComparison(backup1)
        viewModel.selectForComparison(backup2)
        viewModel.clearComparison()

        #expect(viewModel.selectedBackup == nil)
        #expect(viewModel.comparisonBackup == nil)
        #expect(viewModel.currentDiff == nil)
    }

    // MARK: - confirmRestore / restoreVersion

    @Test("confirmRestore sets showRestoreConfirmation and stores backup to restore")
    func testConfirmRestore() {
        let backup = makeBackup()
        let service = SpyVersionHistoryService()
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        viewModel.confirmRestore(backup)

        #expect(viewModel.showRestoreConfirmation)
        #expect(viewModel.backupToRestore?.id == backup.id)
    }

    @Test("restoreVersion delegates to service and reloads backups")
    func testRestoreVersionCallsService() {
        let backup = makeBackup()
        let service = SpyVersionHistoryService(backups: [backup])
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        viewModel.confirmRestore(backup)
        viewModel.restoreVersion()

        #expect(service.restoreCallCount == 1)
        #expect(viewModel.backupToRestore == nil)
        #expect(viewModel.error == nil)
        // loadBackups is called again after restore
        #expect(service.listBackupsCallCount == 1)
    }

    @Test("restoreVersion with nil configPath does nothing")
    func testRestoreVersionNilPath() {
        let backup = makeBackup()
        let service = SpyVersionHistoryService()
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: nil)

        viewModel.confirmRestore(backup)
        viewModel.restoreVersion()

        #expect(service.restoreCallCount == 0)
    }

    @Test("restoreVersion on service error stores error and clears backupToRestore")
    func testRestoreVersionError() {
        let backup = makeBackup()
        let service = SpyVersionHistoryService(shouldThrowOnRestore: true)
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        viewModel.confirmRestore(backup)
        viewModel.restoreVersion()

        #expect(viewModel.error != nil)
        #expect(viewModel.backupToRestore == nil)
    }

    // MARK: - pruneOld

    @Test("pruneOld delegates to service with correct keepCount and reloads backups")
    func testPruneOldDelegates() {
        let service = SpyVersionHistoryService()
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        viewModel.pruneOld(keepCount: 3)

        #expect(service.pruneCallCount == 1)
        #expect(service.lastPruneKeepCount == 3)
        // loadBackups is called after prune
        #expect(service.listBackupsCallCount == 1)
    }

    @Test("pruneOld on service error stores error property")
    func testPruneOldError() {
        let service = SpyVersionHistoryService(shouldThrowOnPrune: true)
        let viewModel = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        viewModel.pruneOld(keepCount: 5)

        #expect(viewModel.error != nil)
    }
}

// MARK: - Spy

@MainActor
private final class SpyVersionHistoryService: ConfigVersionHistoryServiceProtocol {
    private let backupsToReturn: [ConfigBackup]
    private let diffResult: YAMLConfigurationEngine.ConfigDiff?
    private let shouldThrowOnRestore: Bool
    private let shouldThrowOnPrune: Bool
    private let shouldThrowOnDiff: Bool

    var listBackupsCallCount = 0
    var lastListBackupsPath: URL?
    var restoreCallCount = 0
    var pruneCallCount = 0
    var lastPruneKeepCount: Int?

    init(
        backups: [ConfigBackup] = [],
        diffResult: YAMLConfigurationEngine.ConfigDiff? = nil,
        shouldThrowOnRestore: Bool = false,
        shouldThrowOnPrune: Bool = false,
        shouldThrowOnDiff: Bool = false
    ) {
        self.backupsToReturn = backups
        self.diffResult = diffResult
        self.shouldThrowOnRestore = shouldThrowOnRestore
        self.shouldThrowOnPrune = shouldThrowOnPrune
        self.shouldThrowOnDiff = shouldThrowOnDiff
    }

    func listBackups(for configPath: URL) -> [ConfigBackup] {
        listBackupsCallCount += 1
        lastListBackupsPath = configPath
        return backupsToReturn
    }

    func loadBackup(_ backup: ConfigBackup) throws -> String { "" }

    func restoreBackup(_ backup: ConfigBackup, to configPath: URL) throws {
        restoreCallCount += 1
        if shouldThrowOnRestore {
            throw NSError(domain: "SpyError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Restore failed"])
        }
    }

    func diffBetween(_ first: ConfigBackup, _ second: ConfigBackup) throws -> YAMLConfigurationEngine.ConfigDiff {
        if shouldThrowOnDiff {
            throw NSError(domain: "SpyError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Diff failed"])
        }
        return diffResult ?? YAMLConfigurationEngine.ConfigDiff(
            addedRules: [], removedRules: [], modifiedRules: [], before: "", after: ""
        )
    }

    func pruneOldBackups(for configPath: URL, keepCount: Int) throws {
        pruneCallCount += 1
        lastPruneKeepCount = keepCount
        if shouldThrowOnPrune {
            throw NSError(domain: "SpyError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Prune failed"])
        }
    }
}
