//
//  ConfigVersionHistoryViewModel.swift
//  SwiftLintRuleStudio
//
//  ViewModel for browsing and restoring configuration version history
//

import Foundation
import Observation
import SwiftLintRuleStudioCore

@MainActor
@Observable
class ConfigVersionHistoryViewModel {
    var backups: [ConfigBackup] = []
    /// The configuration as it is now, listed above the backups so any backup can be compared
    /// with it. Nil when there's no file.
    private(set) var current: ConfigBackup?
    /// The "before" side of a comparison: badge 1.
    var selectedBackup: ConfigBackup?
    /// The "after" side of a comparison: badge 2. Restoring restores this one.
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
            current = nil
            return
        }
        isLoading = true
        backups = service.listBackups(for: configPath)
        current = Self.currentEntry(at: configPath)
        isLoading = false
        reconcileComparison()
    }

    /// Keeps an open comparison true to what was just loaded: the current configuration may
    /// have changed, and a backup may have been pruned.
    private func reconcileComparison() {
        let sides = [selectedBackup, comparisonBackup].compactMap(\.self)
        guard !sides.isEmpty else { return }
        let stillThere = sides.allSatisfy { side in
            side.id == current?.id || backups.contains { $0.id == side.id }
        }
        guard stillThere else {
            clearComparison()
            return
        }
        if let current {
            if selectedBackup?.id == current.id { selectedBackup = current }
            if comparisonBackup?.id == current.id { comparisonBackup = current }
        }
        // A diff that can't be worked out again — the file may no longer parse — is cleared
        // rather than left describing what the file used to say.
        if !refreshDiff() {
            clearComparison()
        }
    }

    func isCurrent(_ backup: ConfigBackup) -> Bool {
        backup.id == current?.id
    }

    /// How a version is named in the comparison header and labels.
    func label(for backup: ConfigBackup) -> String {
        isCurrent(backup) ? "Current" : backup.formattedDate
    }

    /// The restore button's title for this comparison, naming which side it brings back: the
    /// "after" side. Nil when there's nothing to restore — no comparison, or the current
    /// configuration on the "after" side.
    var restoreLabel: String? {
        guard let before = selectedBackup, let after = comparisonBackup,
              before.id != after.id, !isCurrent(after) else { return nil }
        // The current configuration is the latest state whatever its file date says, so any
        // backup restored over it is the older version.
        if isCurrent(before) { return "Restore Older Version" }
        return after.timestamp < before.timestamp ? "Restore Older Version" : "Restore Newer Version"
    }

    /// Reverses the comparison, so the Summary reads the other way and the restore button
    /// brings back the other version.
    func swapComparison() {
        guard let before = selectedBackup, let after = comparisonBackup else { return }
        // Diff first, so a failure leaves the comparison as it was rather than half swapped.
        do {
            currentDiff = try service.diffBetween(after, before)
            selectedBackup = after
            comparisonBackup = before
        } catch {
            self.error = error
        }
    }

    func selectForComparison(_ backup: ConfigBackup) {
        if comparisonBackup == nil, selectedBackup?.id == backup.id {
            // A second click on the only selected version deselects it, rather than comparing it
            // with itself.
            selectedBackup = nil
        } else if selectedBackup == nil {
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
            // The current configuration just changed, so a comparison with it is out of date.
            clearComparison()
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

    /// Orders a new pair before → after: the current configuration first, so the backup is what
    /// a restore would bring back; otherwise the older version first.
    private func generateDiff() {
        guard let first = selectedBackup,
              let second = comparisonBackup else { return }

        let firstIsBefore = isCurrent(first) || (!isCurrent(second) && first.timestamp <= second.timestamp)
        selectedBackup = firstIsBefore ? first : second
        comparisonBackup = firstIsBefore ? second : first
        refreshDiff()
    }

    /// False when the diff couldn't be worked out; `error` then says why.
    @discardableResult
    private func refreshDiff() -> Bool {
        guard let before = selectedBackup, let after = comparisonBackup else { return true }
        do {
            currentDiff = try service.diffBetween(before, after)
            return true
        } catch {
            self.error = error
            return false
        }
    }

    private static func currentEntry(at configPath: URL) -> ConfigBackup? {
        guard FileManager.default.fileExists(atPath: configPath.path) else { return nil }
        let values = try? configPath.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return ConfigBackup(
            id: "current:\(configPath.path)",
            path: configPath,
            timestamp: values?.contentModificationDate ?? .now,
            fileSize: Int64(values?.fileSize ?? 0)
        )
    }
}
