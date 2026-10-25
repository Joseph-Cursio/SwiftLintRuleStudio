//
//  ConfigBackupStore.swift
//  SwiftLintRuleStudio
//
//  Where the app keeps the backups it takes before writing a configuration: in its own
//  Application Support folder, not beside the file in the user's project.
//

import CryptoKit
import Foundation

/// Whether this process is a test run rather than the app a person is using. Errs toward "the
/// app": an unknown host stores backups for real.
///
/// - Xcode-hosted tests: XCTest sets `XCTestConfigurationFilePath` (sometimes to "", hence
///   `!= nil`).
/// - UI tests: the app under test is launched with `-uiTesting`.
/// - `swift test`: neither of those, and the test binary is loaded with dlopen rather than as a
///   bundle — but it links XCTest, so `XCTestCase` is present. The `.xctest` bundle check
///   covers hosts that load test bundles the usual way.
enum TestRun {
    static let isActive: Bool = {
        let process = ProcessInfo.processInfo
        return process.environment["XCTestConfigurationFilePath"] != nil
            || process.arguments.contains("-uiTesting")
            || Bundle.allBundles.contains { $0.bundleURL.pathExtension == "xctest" }
            || NSClassFromString("XCTestCase") != nil
    }()
}

/// The backups of every configuration file the app writes, one folder per file.
///
/// Backups used to be written beside the configuration as `.swiftlint.yml.<seconds>.backup`,
/// one untracked file in the user's repository per save (reported with issue #83). The store
/// keeps them in the app's own data instead:
///
/// ```
/// <root>/<project folder>-<hash>/.swiftlint.yml.1700000000.backup
///                               /config-path.txt
///                               /Earlier/.swiftlint.yml.1690000000.backup
/// ```
///
/// The folder is keyed by the configuration's path, so a project that moves starts a new
/// history; `config-path.txt` records which file a folder belongs to. Backups left beside a
/// file by earlier versions are still listed (``backups(for:)``) and can be moved in on request
/// (``moveLegacyBackups(of:discard:)``), but nothing moves or deletes them automatically. Moved
/// ones go into `Earlier`, which retention never prunes: moving them must not expose them to a
/// limit they were never under.
///
/// The two editions keep separate stores: the sandboxed one's Application Support is inside
/// its container.
public struct ConfigBackupStore: Sendable {
    public let root: URL
    /// How many backups of each configuration the store keeps after a save, in all: the oldest —
    /// the file as it was before the app first changed it — and the newest `retention - 1`.
    public let retention: Int

    public init(root: URL, retention: Int = 50) {
        self.root = root
        self.retention = max(retention, 2)
    }

    // MARK: - Location

    /// The store saves use unless told otherwise: `Application Support/SwiftLintRuleStudio/Config
    /// Backups`, except in a test run, which gets a folder of its own under the temporary
    /// directory — a test must never write into a developer's real Application Support.
    public static let standard: Self = {
        let fileManager = FileManager.default
        if TestRun.isActive {
            let base = fileManager.temporaryDirectory
                .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
            let processID = ProcessInfo.processInfo.processIdentifier
            return Self(root: base.appendingPathComponent(
                "config-backups-\(processID)-\(UUID().uuidString)",
                isDirectory: true
            ))
        }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return Self(root: appSupport
            .appendingPathComponent("SwiftLintRuleStudio", isDirectory: true)
            .appendingPathComponent("Config Backups", isDirectory: true))
    }()

    /// The folder holding the backups of `configPath`. Pure: it creates nothing.
    public func directory(for configPath: URL) -> URL {
        let canonical = Self.canonicalPath(of: configPath)
        let digest = SHA256.hash(data: Data(canonical.utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
        // Named from the resolved folder too, so a project opened through a symlinked folder
        // finds the same history as through its real path.
        let project = Self.readableName(URL(fileURLWithPath: canonical).deletingLastPathComponent().lastPathComponent)
        return root.appendingPathComponent("\(project)-\(digest)", isDirectory: true)
    }

    /// Where backups moved in from the project folder are kept, apart from the store's own so
    /// retention never prunes them.
    public func earlierDirectory(for configPath: URL) -> URL {
        directory(for: configPath).appendingPathComponent("Earlier", isDirectory: true)
    }

    /// The configuration's folder with symlinks resolved, plus its file name.
    ///
    /// Not the file resolved: that answers differently once the file is deleted — exactly when
    /// someone opens Version History to get it back — and it follows a symlinked configuration
    /// to wherever it points, until the next save replaces the link with a file.
    static func canonicalPath(of configPath: URL) -> String {
        configPath.standardizedFileURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(configPath.lastPathComponent)
            .path
    }

    /// A folder name a person can recognize, kept short enough that the hash still fits under
    /// the file system's 255-byte limit.
    private static func readableName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return cleaned.isEmpty ? "config" : String(cleaned.prefix(64))
    }

    // MARK: - Taking backups

    /// Copies `configPath`'s current contents into the store, stamped `date`.
    ///
    /// Returns nil, creating nothing, when there is no file to back up, or when it matches the
    /// newest backup: a save that changes nothing, or one retried after a failed write, would
    /// otherwise push real versions out. The bytes are copied, not the file, so a symlink or a
    /// Finder lock doesn't come along. Two backups in the same second never overwrite each
    /// other; the later one takes the next free second.
    @discardableResult
    public func backUp(_ configPath: URL, at date: Date) throws -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: configPath.path) else { return nil }
        let contents = try Data(contentsOf: configPath)
        if let newest = storedBackups(for: configPath).first,
           (try? Data(contentsOf: newest.path)) == contents {
            return nil
        }
        try fileManager.createDirectory(at: directory(for: configPath), withIntermediateDirectories: true)
        labelFolder(for: configPath)
        let destination = nextBackupURL(for: configPath, at: date) { fileManager.fileExists(atPath: $0.path) }
        try contents.write(to: destination, options: .withoutOverwriting)
        return destination
    }

    /// Where a backup of `configPath` taken at `date` goes: `<file name>.<seconds>.backup` in
    /// its folder, a second later for each name `exists` reports taken.
    public func nextBackupURL(for configPath: URL, at date: Date, exists: (URL) -> Bool) -> URL {
        nextBackupURL(in: directory(for: configPath), for: configPath, at: date, exists: exists)
    }

    private func nextBackupURL(in folder: URL, for configPath: URL, at date: Date, exists: (URL) -> Bool) -> URL {
        var seconds = Int(date.timeIntervalSince1970)
        while true {
            let candidate = folder.appendingPathComponent(
                Self.backupName(of: configPath.lastPathComponent, seconds: seconds)
            )
            if !exists(candidate) { return candidate }
            seconds += 1
        }
    }

    /// Removes the store's backups of `configPath` beyond ``retention``, keeping the oldest.
    ///
    /// Over the limit, an older backup whose contents a newer one also holds goes first — a
    /// restore's safety copy often repeats a version already kept, and counting repeats would
    /// push distinct versions out. Only then are the oldest dropped, keeping the very oldest.
    ///
    /// Call it after a write succeeds, not before: a write that fails must not cost history.
    /// Best effort, one file at a time — a backup that can't be removed is skipped rather than
    /// failing a save that already happened. Backups in the project folder or in `Earlier` are
    /// never touched.
    public func applyRetention(to configPath: URL) {
        var stored = storedBackups(for: configPath)
        guard stored.count > retention else { return }
        var seen: Set<Data> = []
        stored = stored.filter { backup in
            guard let contents = try? Data(contentsOf: backup.path), !seen.insert(contents).inserted else {
                return true
            }
            return (try? FileManager.default.removeItem(at: backup.path)) == nil
        }
        guard stored.count > retention, let oldest = stored.last else { return }
        let kept = Set(stored.prefix(retention - 1).map(\.id)).union([oldest.id])
        for backup in stored where !kept.contains(backup.id) {
            try? FileManager.default.removeItem(at: backup.path)
        }
    }

    // MARK: - Listing

    /// Every backup of `configPath`, newest first: the store's own, those moved in from the
    /// project folder, and any still beside the file. Each place gives its backups their own
    /// ids, so a name that turns up in two places is listed twice rather than hidden.
    public func backups(for configPath: URL) -> [ConfigBackup] {
        (storedBackups(for: configPath) + earlierBackups(for: configPath) + Self.legacyBackups(beside: configPath))
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// The store's own backups of `configPath`, newest first — the ones retention manages.
    public func storedBackups(for configPath: URL) -> [ConfigBackup] {
        Self.backups(in: directory(for: configPath), of: configPath.lastPathComponent, idPrefix: "")
    }

    /// The backups moved in from the project folder, newest first.
    public func earlierBackups(for configPath: URL) -> [ConfigBackup] {
        Self.backups(in: earlierDirectory(for: configPath), of: configPath.lastPathComponent, idPrefix: "Earlier/")
    }

    /// The backups an earlier version left beside `configPath`, newest first.
    public static func legacyBackups(beside configPath: URL) -> [ConfigBackup] {
        backups(in: configPath.deletingLastPathComponent(), of: configPath.lastPathComponent, idPrefix: "Project/")
    }

    private static func backups(in folder: URL, of configFileName: String, idPrefix: String) -> [ConfigBackup] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else {
            return []
        }
        return contents.compactMap { url -> ConfigBackup? in
            let name = url.lastPathComponent
            guard let timestamp = backupTimestamp(name, of: configFileName) else { return nil }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { return nil }
            return ConfigBackup(
                id: idPrefix + name,
                path: url,
                timestamp: timestamp,
                fileSize: values?.fileSize.map(Int64.init) ?? 0
            )
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    static func backupName(of configFileName: String, seconds: Int) -> String {
        "\(configFileName).\(seconds).backup"
    }

    /// The time in a backup's name, `<file name>.<seconds>.backup`, with exactly ten digits of
    /// seconds — what the app has always written. Anything else (a backup someone made by hand,
    /// `1e9`, `nan`) isn't the app's, so it is never listed, moved or pruned.
    static func backupTimestamp(_ name: String, of configFileName: String) -> Date? {
        let prefix = "\(configFileName)."
        let suffix = ".backup"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix),
              name.count == prefix.count + 10 + suffix.count else {
            return nil
        }
        let digits = name.dropFirst(prefix.count).dropLast(suffix.count)
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }), let seconds = Int(digits) else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    // MARK: - Moving earlier backups in

    /// Moves the backups an earlier version left beside `configPath` into the store's `Earlier`
    /// folder, so the project folder holds only the configuration. Returns how many left it.
    ///
    /// Only ever on request. Each backup is copied in first and only then handed to `discard`
    /// (the Trash, by default), so a failure at either step leaves it where it was rather than
    /// lost; a copy whose original can't be discarded is taken back out. Oldest first, so a
    /// name already taken by different contents moves to the next free second without jumping
    /// ahead of a newer backup; one the folder already holds byte for byte is just discarded.
    @discardableResult
    public func moveLegacyBackups(
        of configPath: URL,
        discard: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws -> Int {
        let legacy = Self.legacyBackups(beside: configPath)
        guard !legacy.isEmpty else { return 0 }
        let fileManager = FileManager.default
        let folder = earlierDirectory(for: configPath)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        labelFolder(for: configPath)

        var moved = 0
        for backup in legacy.reversed() {
            guard let contents = try? Data(contentsOf: backup.path) else { continue }
            let sameName = folder.appendingPathComponent(backup.path.lastPathComponent)
            var copy: URL?
            if (try? Data(contentsOf: sameName)) != contents {
                let destination = nextBackupURL(in: folder, for: configPath, at: backup.timestamp) {
                    fileManager.fileExists(atPath: $0.path)
                }
                guard (try? contents.write(to: destination, options: .withoutOverwriting)) != nil else {
                    continue
                }
                copy = destination
            }
            do {
                try discard(backup.path)
                moved += 1
            } catch {
                if let copy { try? fileManager.removeItem(at: copy) }
            }
        }
        return moved
    }

    /// Notes which file a folder's backups belong to, for anyone browsing the store. Best effort:
    /// it is a label, not something a backup depends on, and it needs the folder to exist.
    public func labelFolder(for configPath: URL) {
        let label = directory(for: configPath).appendingPathComponent("config-path.txt")
        guard !FileManager.default.fileExists(atPath: label.path) else { return }
        try? (configPath.standardizedFileURL.path + "\n").write(to: label, atomically: true, encoding: .utf8)
    }
}
