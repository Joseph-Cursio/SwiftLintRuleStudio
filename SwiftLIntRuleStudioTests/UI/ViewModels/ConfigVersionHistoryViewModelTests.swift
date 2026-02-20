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
        timestamp: Date = Date(),
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
        let vm = ConfigVersionHistoryViewModel(service: service, configPath: nil)
        #expect(vm.backups.isEmpty)
        #expect(vm.selectedBackup == nil)
        #expect(vm.comparisonBackup == nil)
        #expect(vm.currentDiff == nil)
        #expect(!vm.isLoading)
        #expect(!vm.showRestoreConfirmation)
        #expect(vm.backupToRestore == nil)
        #expect(vm.error == nil)
    }

    // MARK: - loadBackups

    @Test("loadBackups with nil configPath returns empty list and does not call service")
    func testLoadBackupsNilPath() {
        let service = SpyVersionHistoryService()
        let vm = ConfigVersionHistoryViewModel(service: service, configPath: nil)
        vm.loadBackups()
        #expect(vm.backups.isEmpty)
        #expect(service.listBackupsCallCount == 0)
    }

    @Test("loadBackups populates backups from service and clears isLoading")
    func testLoadBackupsPopulates() {
        let backup1 = makeBackup(timestamp: Date(timeIntervalSince1970: 1_000))
        let backup2 = makeBackup(timestamp: Date(timeIntervalSince1970: 2_000))
        let service = SpyVersionHistoryService(backups: [backup1, backup2])
        let vm = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        vm.loadBackups()

        #expect(vm.backups.count == 2)
        #expect(!vm.isLoading)
        #expect(service.listBackupsCallCount == 1)
    }

    @Test("loadBackups passes the correct configPath to the service")
    func testLoadBackupsPassesCorrectPath() {
        let expectedPath = URL(fileURLWithPath: "/project/.swiftlint.yml")
        let service = SpyVersionHistoryService()
        let vm = ConfigVersionHistoryViewModel(service: service, configPath: expectedPath)

        vm.loadBackups()

        #expect(service.lastListBackupsPath == expectedPath)
    }

    // MARK: - selectForComparison state machine

    @Test("First selectForComparison call sets selectedBackup only")
    func testFirstSelectionSetsSelectedBackup() {
        let backup = makeBackup()
        let service = SpyVersionHistoryService(backups: [backup])
        let vm = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        vm.selectForComparison(backup)

        #expect(vm.selectedBackup?.id == backup.id)
        #expect(vm.comparisonBackup == nil)
        #expect(vm.currentDiff == nil)
    }

    @Test("Second selectForComparison call sets comparisonBackup and generates diff")
    func testSecondSelectionGeneratesDiff() {
        let backup1 = makeBackup(timestamp: Date(timeIntervalSince1970: 1_000))
        let backup2 = makeBackup(timestamp: Date(timeIntervalSince1970: 2_000))
        let diff = makeDiff(addedRules: ["force_cast"])
        let service = SpyVersionHistoryService(backups: [backup1, backup2], diffResult: diff)
        let vm = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        vm.selectForComparison(backup1)
        vm.selectForComparison(backup2)

        #expect(vm.selectedBackup?.id == backup1.id)
        #expect(vm.comparisonBackup?.id == backup2.id)
        #expect(vm.currentDiff?.addedRules.contains("force_cast") == true)
    }

    @Test("Third selectForComparison call resets selection to the new backup")
    func testThirdSelectionResetsState() {
        let backup1 = makeBackup(timestamp: Date(timeIntervalSince1970: 1_000))
        let backup2 = makeBackup(timestamp: Date(timeIntervalSince1970: 2_000))
        let backup3 = makeBackup(timestamp: Date(timeIntervalSince1970: 3_000))
        let service = SpyVersionHistoryService(backups: [backup1, backup2, backup3])
        let vm = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        vm.selectForComparison(backup1)
        vm.selectForComparison(backup2)
        vm.selectForComparison(backup3)

        #expect(vm.selectedBackup?.id == backup3.id)
        #expect(vm.comparisonBackup == nil)
        #expect(vm.currentDiff == nil)
    }

    @Test("Diff generation error is stored in error property")
    func testDiffGenerationErrorStoredInError() {
        let backup1 = makeBackup()
        let backup2 = makeBackup()
        let service = SpyVersionHistoryService(shouldThrowOnDiff: true)
        let vm = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        vm.selectForComparison(backup1)
        vm.selectForComparison(backup2)

        #expect(vm.error != nil)
        #expect(vm.currentDiff == nil)
    }

    // MARK: - clearComparison

    @Test("clearComparison resets all selection state to nil")
    func testClearComparison() {
        let backup1 = makeBackup()
        let backup2 = makeBackup()
        let diff = makeDiff()
        let service = SpyVersionHistoryService(diffResult: diff)
        let vm = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        vm.selectForComparison(backup1)
        vm.selectForComparison(backup2)
        vm.clearComparison()

        #expect(vm.selectedBackup == nil)
        #expect(vm.comparisonBackup == nil)
        #expect(vm.currentDiff == nil)
    }

    // MARK: - confirmRestore / restoreVersion

    @Test("confirmRestore sets showRestoreConfirmation and stores backup to restore")
    func testConfirmRestore() {
        let backup = makeBackup()
        let service = SpyVersionHistoryService()
        let vm = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        vm.confirmRestore(backup)

        #expect(vm.showRestoreConfirmation == true)
        #expect(vm.backupToRestore?.id == backup.id)
    }

    @Test("restoreVersion delegates to service and reloads backups")
    func testRestoreVersionCallsService() {
        let backup = makeBackup()
        let service = SpyVersionHistoryService(backups: [backup])
        let vm = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        vm.confirmRestore(backup)
        vm.restoreVersion()

        #expect(service.restoreCallCount == 1)
        #expect(vm.backupToRestore == nil)
        #expect(vm.error == nil)
        // loadBackups is called again after restore
        #expect(service.listBackupsCallCount == 1)
    }

    @Test("restoreVersion with nil configPath does nothing")
    func testRestoreVersionNilPath() {
        let backup = makeBackup()
        let service = SpyVersionHistoryService()
        let vm = ConfigVersionHistoryViewModel(service: service, configPath: nil)

        vm.confirmRestore(backup)
        vm.restoreVersion()

        #expect(service.restoreCallCount == 0)
    }

    @Test("restoreVersion on service error stores error and clears backupToRestore")
    func testRestoreVersionError() {
        let backup = makeBackup()
        let service = SpyVersionHistoryService(shouldThrowOnRestore: true)
        let vm = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        vm.confirmRestore(backup)
        vm.restoreVersion()

        #expect(vm.error != nil)
        #expect(vm.backupToRestore == nil)
    }

    // MARK: - pruneOld

    @Test("pruneOld delegates to service with correct keepCount and reloads backups")
    func testPruneOldDelegates() {
        let service = SpyVersionHistoryService()
        let vm = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        vm.pruneOld(keepCount: 3)

        #expect(service.pruneCallCount == 1)
        #expect(service.lastPruneKeepCount == 3)
        // loadBackups is called after prune
        #expect(service.listBackupsCallCount == 1)
    }

    @Test("pruneOld on service error stores error property")
    func testPruneOldError() {
        let service = SpyVersionHistoryService(shouldThrowOnPrune: true)
        let vm = ConfigVersionHistoryViewModel(service: service, configPath: Self.configPath)

        vm.pruneOld(keepCount: 5)

        #expect(vm.error != nil)
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
