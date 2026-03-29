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
    func listBackups(for configPath: URL) -> [ConfigBackup]
    func loadBackup(_ backup: ConfigBackup) throws -> String
    func restoreBackup(_ backup: ConfigBackup, to configPath: URL) throws
    func diffBetween(
        _ first: ConfigBackup,
        _ second: ConfigBackup
    ) throws -> YAMLConfigurationEngine.ConfigDiff
    func pruneOldBackups(for configPath: URL, keepCount: Int) throws
}

/// Service for browsing and restoring configuration version history
public final class ConfigVersionHistoryService: ConfigVersionHistoryServiceProtocol {

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

            let fileSize: Int64 = (try? url.resourceValues(
                forKeys: [.fileSizeKey]
            ).fileSize.map(Int64.init)) ?? 0

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
        try String(contentsOf: backup.path, encoding: .utf8)
    }

    public func restoreBackup(_ backup: ConfigBackup, to configPath: URL) throws {
        let fileManager = FileManager.default

        // Create a safety backup of current config before restoring
        if fileManager.fileExists(atPath: configPath.path) {
            let timestamp = Int(Date.now.timeIntervalSince1970)
            let safetyBackupName = "\(configPath.lastPathComponent).\(timestamp).backup"
            let safetyBackupPath = configPath.deletingLastPathComponent()
                .appendingPathComponent(safetyBackupName)
            try fileManager.copyItem(at: configPath, to: safetyBackupPath)
        }

        // Copy backup content to config path
        let backupContent = try String(contentsOf: backup.path, encoding: .utf8)
        try backupContent.write(to: configPath, atomically: true, encoding: .utf8)
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
