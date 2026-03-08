//
//  ConfigVersionHistoryViewModel.swift
//  SwiftLintRuleStudio
//
//  ViewModel for browsing and restoring configuration version history
//

import Foundation
import Observation

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
        isLoading = false
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

        do {
            currentDiff = try service.diffBetween(first, second)
        } catch {
            self.error = error
        }
    }
}
