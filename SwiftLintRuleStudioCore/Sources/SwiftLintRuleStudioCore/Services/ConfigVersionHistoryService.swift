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
}

/// Service for browsing and restoring configuration version history
public final class ConfigVersionHistoryService: ConfigVersionHistoryServiceProtocol {

    private let now: DateProvider
    private let files: FileIO

    /// Both dependencies default to the real thing, so no existing call site changes.
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
    /// `diffBetween` deliberately still writes to disk. Its two writes exist to hand content to
    /// `YAMLConfigurationEngine(configPath:)`, which takes a path and reads it back, so routing
    /// them through this seam would move the dependency rather than remove it.
    public init(now: DateProvider = .system, files: FileIO = .live) {
        self.now = now
        self.files = files
    }

    public func listBackups(for configPath: URL) -> [ConfigBackup] {
        let directory = configPath.deletingLastPathComponent()
        let configFileName = configPath.lastPathComponent
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: []
        ) else {
            return []
        }

        // Match pattern: {configFileName}.{timestamp}.backup
        let prefix = "\(configFileName)."
        let suffix = ".backup"

        return contents.compactMap { url -> ConfigBackup? in
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix) && name.hasSuffix(suffix) else { return nil }

            // Extract timestamp
            let startIndex = name.index(name.startIndex, offsetBy: prefix.count)
            let endIndex = name.index(name.endIndex, offsetBy: -suffix.count)
            guard startIndex < endIndex else { return nil }

            let timestampStr = String(name[startIndex..<endIndex])
            guard let timestamp = TimeInterval(timestampStr) else { return nil }

            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
            let fileSize: Int64 = resourceValues?.fileSize.map(Int64.init) ?? 0

            return ConfigBackup(
                id: name,
                path: url,
                timestamp: Date(timeIntervalSince1970: timestamp),
                fileSize: fileSize
            )
        }
        .sorted { $0.timestamp > $1.timestamp } // Newest first
    }

    public func loadBackup(_ backup: ConfigBackup) throws -> String {
        try files.read(backup.path)
    }

    public func restoreBackup(_ backup: ConfigBackup, to configPath: URL) throws {
        // Read first, and write only after the read has succeeded. The order is the contract:
        // a backup that cannot be read must leave the current configuration untouched, and
        // reading last would overwrite it before finding out.
        let backupContent = try files.read(backup.path)

        // Safety-net the current config before replacing it.
        if files.exists(configPath) {
            let timestamp = Int(now().timeIntervalSince1970)
            let safetyBackupName = "\(configPath.lastPathComponent).\(timestamp).backup"
            let safetyBackupPath = configPath.deletingLastPathComponent()
                .appendingPathComponent(safetyBackupName)
            try files.copy(configPath, safetyBackupPath)
        }

        try files.write(backupContent, configPath)
    }

    public func diffBetween(
        _ first: ConfigBackup,
        _ second: ConfigBackup
    ) throws -> YAMLConfigurationEngine.ConfigDiff {
        let firstContent = try String(contentsOf: first.path, encoding: .utf8)
        let secondContent = try String(contentsOf: second.path, encoding: .utf8)

        // Load first config into a temporary engine
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tempPath = tempDir.appendingPathComponent(".swiftlint.yml")

        // Load first as "current"
        try firstContent.write(to: tempPath, atomically: true, encoding: .utf8)
        let tempEngine = YAMLConfigurationEngine(configPath: tempPath)
        try tempEngine.load()
        let firstConfig = tempEngine.getConfig()

        // Load second as proposed
        try secondContent.write(to: tempPath, atomically: true, encoding: .utf8)
        let tempEngine2 = YAMLConfigurationEngine(configPath: tempPath)
        try tempEngine2.load()
        let secondConfig = tempEngine2.getConfig()

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
            after: secondContent
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
}
