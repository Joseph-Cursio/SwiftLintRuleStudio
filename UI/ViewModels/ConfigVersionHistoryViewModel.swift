//
//  ConfigVersionHistoryViewModel.swift
//  SwiftLintRuleStudio
//
//  ViewModel for browsing and restoring configuration version history
//

import Foundation
import Observation
import SwiftLintRuleStudioCore

/// Some backups in the project folder couldn't be sent to the Trash, so they were left there.
struct LegacyBackupsNotMovedError: LocalizedError {
    let count: Int

    var errorDescription: String? {
        let backups = count == 1 ? "1 backup" : "\(count) backups"
        return "\(backups) couldn't be moved to the Trash, so \(count == 1 ? "it is" : "they are") "
            + "still in the project folder. Nothing was lost."
    }
}

@MainActor
@Observable
class ConfigVersionHistoryViewModel {
    var backups: [ConfigBackup] = []
    var selectedBackup: ConfigBackup?
    var comparisonBackup: ConfigBackup?
    var currentDiff: YAMLConfigurationEngine.ConfigDiff?
    var isLoading: Bool = false
    var error: Error?
    var showError: Bool {
        get { error != nil }
        set { if !newValue { error = nil } }
    }
    var showRestoreConfirmation: Bool = false
    var backupToRestore: ConfigBackup?
    /// Backups an earlier version left in the project folder, beside the configuration.
    var legacyBackupCount: Int = 0
    /// The folder the app keeps this configuration's backups in, once it exists.
    var backupsFolder: URL?

    private let service: ConfigVersionHistoryServiceProtocol
    private let configPath: URL?

    init(service: ConfigVersionHistoryServiceProtocol, configPath: URL?) {
        self.service = service
        self.configPath = configPath
    }

    func loadBackups() {
        guard let configPath = configPath else {
            backups = []
            return
        }
        isLoading = true
        backups = service.listBackups(for: configPath)
        // Selections are values; after a move or a prune they can name files that are gone.
        // Keep only those still listed, and drop a comparison that lost a side.
        selectedBackup = selectedBackup.flatMap { kept in backups.first { $0.id == kept.id } }
        comparisonBackup = comparisonBackup.flatMap { kept in backups.first { $0.id == kept.id } }
        if selectedBackup == nil || comparisonBackup == nil {
            currentDiff = nil
        }
        legacyBackupCount = service.legacyBackupCount(for: configPath)
        backupsFolder = service.backupsFolder(for: configPath).flatMap { folder in
            FileManager.default.fileExists(atPath: folder.path) ? folder : nil
        }
        isLoading = false
    }

    /// Moves the backups an earlier version left in the project folder into the app's store.
    /// The originals go to the Trash, so the project folder holds only the configuration.
    func moveLegacyBackups() {
        guard let configPath = configPath else { return }
        do {
            _ = try service.moveLegacyBackups(for: configPath)
            error = nil
        } catch {
            self.error = error
        }
        loadBackups()
        // A backup that couldn't go to the Trash stays put rather than being lost, and the
        // service says nothing about it; without this the button would just appear to do nothing.
        if error == nil, legacyBackupCount > 0 {
            error = LegacyBackupsNotMovedError(count: legacyBackupCount)
        }
    }

    func selectForComparison(_ backup: ConfigBackup) {
        if selectedBackup == nil {
            selectedBackup = backup
        } else if comparisonBackup == nil {
            comparisonBackup = backup
            generateDiff()
        } else {
            // Reset and start new selection
            selectedBackup = backup
            comparisonBackup = nil
            currentDiff = nil
        }
    }

    func clearComparison() {
        selectedBackup = nil
        comparisonBackup = nil
        currentDiff = nil
    }

    func confirmRestore(_ backup: ConfigBackup) {
        backupToRestore = backup
        showRestoreConfirmation = true
    }

    func restoreVersion() {
        guard let backup = backupToRestore, let configPath = configPath else { return }
        do {
            try service.restoreBackup(backup, to: configPath)
            error = nil
            // Reload backups list (new safety backup was created)
            loadBackups()
            NotificationCenter.default.post(
                name: .configurationDidRestore,
                object: nil
            )
        } catch {
            self.error = error
        }
        backupToRestore = nil
    }

    func pruneOld(keepCount: Int = 10) {
        guard let configPath = configPath else { return }
        do {
            try service.pruneOldBackups(for: configPath, keepCount: keepCount)
            loadBackups()
        } catch {
            self.error = error
        }
    }

    private func generateDiff() {
        guard let first = selectedBackup,
              let second = comparisonBackup else { return }

        // Always order chronologically: earlier = before, later = after
        let earlier: ConfigBackup
        let later: ConfigBackup
        if first.timestamp <= second.timestamp {
            earlier = first
            later = second
        } else {
            earlier = second
            later = first
        }
        selectedBackup = earlier
        comparisonBackup = later

        do {
            currentDiff = try service.diffBetween(earlier, later)
        } catch {
            self.error = error
        }
    }
}
