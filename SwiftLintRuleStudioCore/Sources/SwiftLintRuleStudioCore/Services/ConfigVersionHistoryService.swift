//
//  ConfigVersionHistoryService.swift
//  SwiftLintRuleStudio
//
//  Browse and restore previous configuration versions from timestamped backup files
//

import Foundation

/// Represents a backup of a configuration file
public struct ConfigBackup: Identifiable, Sendable {
    public let id: String
    public let path: URL
    public let timestamp: Date
    public let fileSize: Int64

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public init(id: String, path: URL, timestamp: Date, fileSize: Int64) {
        self.id = id
        self.path = path
        self.timestamp = timestamp
        self.fileSize = fileSize
    }
}

/// Protocol for version history service
public protocol ConfigVersionHistoryServiceProtocol {
    /// List available backups for a configuration file
    func listBackups(for configPath: URL) -> [ConfigBackup]
    /// Load the content of a backup file
    func loadBackup(_ backup: ConfigBackup) throws -> String
    /// Restore a backup to the specified configuration path
    func restoreBackup(_ backup: ConfigBackup, to configPath: URL) throws
    /// Compute the diff between two configuration backups
    func diffBetween(
        _ first: ConfigBackup,
        _ second: ConfigBackup
    ) throws -> YAMLConfigurationEngine.ConfigDiff
    /// Remove old backups, keeping only the specified count
    func pruneOldBackups(for configPath: URL, keepCount: Int) throws
    /// How many backups an earlier version left beside the configuration, in the project folder
    func legacyBackupCount(for configPath: URL) -> Int
    /// Move those backups out of the project folder into the app's own store
    func moveLegacyBackups(for configPath: URL) throws -> Int
    /// The folder the app keeps this configuration's backups in
    func backupsFolder(for configPath: URL) -> URL?
}

/// Service for browsing and restoring configuration version history
public final class ConfigVersionHistoryService: ConfigVersionHistoryServiceProtocol {

    private let now: DateProvider
    private let files: FileIO
    private let backups: ConfigBackupStore
    private let discard: @Sendable (URL) throws -> Void

    /// Every dependency defaults to the real thing, so no existing call site changes.
    ///
    /// The clock is observable here rather than incidental: the safety backup is named
    /// `{config}.{unix timestamp}.backup`, and `listBackups` parses that stamp back out. Choose
    /// the instant and the round trip becomes a law — a backup taken at `t` is listed at `t`.
    ///
    /// `files` covers the read/write/copy this service performs on behalf of a restore. It is
    /// injected for the failure paths rather than the happy one: whether a restore that cannot
    /// read its backup leaves the user's configuration untouched is not something you want to
    /// discover from a bug report, and it cannot be reached on a real file system without
    /// arranging a permission error.
    ///
    /// `backups` is where the history lives: the app's own store, not the project folder. Backups
    /// an earlier version left beside the configuration are listed alongside the store's, and
    /// `discard` is what moving them out does with the originals: the Trash, unless a test says
    /// otherwise.
    public init(
        now: DateProvider = .system,
        files: FileIO = .live,
        backups: ConfigBackupStore = .standard,
        discard: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        }
    ) {
        self.now = now
        self.files = files
        self.backups = backups
        self.discard = discard
    }

    public func listBackups(for configPath: URL) -> [ConfigBackup] {
        backups.backups(for: configPath)
    }

    public func loadBackup(_ backup: ConfigBackup) throws -> String {
        try files.read(backup.path)
    }

    public func restoreBackup(_ backup: ConfigBackup, to configPath: URL) throws {
        // Read first, and write only after the read has succeeded. The order is the contract:
        // a backup that cannot be read must leave the current configuration untouched, and
        // reading last would overwrite it before finding out.
        let backupContent = try files.read(backup.path)

        // Safety-net the current config before replacing it — into the store, under the next
        // free second, so it never lands in the project folder or overwrites a backup a save
        // took in the same second.
        if files.exists(configPath) {
            let safetyBackupPath = backups.nextBackupURL(for: configPath, at: now(), exists: files.exists)
            try files.copy(configPath, safetyBackupPath)
            backups.labelFolder(for: configPath)
        }

        try files.write(backupContent, configPath)
    }

    public func diffBetween(
        _ first: ConfigBackup,
        _ second: ConfigBackup
    ) throws -> YAMLConfigurationEngine.ConfigDiff {
        let firstContent = try String(contentsOf: first.path, encoding: .utf8)
        let secondContent = try String(contentsOf: second.path, encoding: .utf8)

        // Both backups are already strings. This used to create a temporary directory, write
        // each string into the same file in turn, and construct an engine per write to read it
        // back — two filesystem round trips to reach a pure parse.
        let firstConfig = try YAMLConfigurationEngine.parse(firstContent)
        let secondConfig = try YAMLConfigurationEngine.parse(secondContent)

        let firstRules = Set(firstConfig.rules.keys)
        let secondRules = Set(secondConfig.rules.keys)

        let added = Array(secondRules.subtracting(firstRules)).sorted()
        let removed = Array(firstRules.subtracting(secondRules)).sorted()
        let modified = firstRules.intersection(secondRules).filter { ruleId in
            firstConfig.rules[ruleId] != secondConfig.rules[ruleId]
        }

        return YAMLConfigurationEngine.ConfigDiff(
            addedRules: added,
            removedRules: removed,
            modifiedRules: Array(modified).sorted(),
            before: firstContent,
            after: secondContent,
            changes: ConfigChangeSummary(from: firstConfig, to: secondConfig)
        )
    }

    public func pruneOldBackups(for configPath: URL, keepCount: Int) throws {
        let backups = listBackups(for: configPath)
        guard backups.count > keepCount else { return }

        let toRemove = backups.dropFirst(keepCount) // Already sorted newest first
        for backup in toRemove {
            try FileManager.default.removeItem(at: backup.path)
        }
    }

    public func legacyBackupCount(for configPath: URL) -> Int {
        ConfigBackupStore.legacyBackups(beside: configPath).count
    }

    public func moveLegacyBackups(for configPath: URL) throws -> Int {
        try backups.moveLegacyBackups(of: configPath, discard: discard)
    }

    public func backupsFolder(for configPath: URL) -> URL? {
        backups.directory(for: configPath)
    }
}

/// Defaults for the three additions, so a test double written before them still conforms and
/// reports no backups in the project folder.
public extension ConfigVersionHistoryServiceProtocol {
    /// None: a service that doesn't know about the project folder has nothing there.
    func legacyBackupCount(for _: URL) -> Int { 0 }
    /// Moves nothing.
    func moveLegacyBackups(for _: URL) throws -> Int { 0 }
    /// No folder to show.
    func backupsFolder(for _: URL) -> URL? { nil }
}
