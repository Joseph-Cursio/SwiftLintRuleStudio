//
//  ConfigVersionHistoryClockTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  A backup's timestamp round-trips through its filename. While the service read `Date.now`
//  inline there was nothing to compare the parsed stamp against; with the clock injected
//  (see DateProvider) the encode/decode pair is a law.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@Suite("Config version history — the backup timestamp round-trips")
struct ConfigVersionHistoryClockTests {

    /// A backup written at `t` is listed with timestamp `t`.
    ///
    /// The safety backup is named `{config}.{unix timestamp}.backup`, in the backup store, and
    /// `listBackups` parses that stamp back out, so the clock is observable rather than
    /// incidental. With `Date.now` read inline there was nothing to compare the parsed value
    /// against; with the instant chosen, the encode/decode pair is a law.
    @Test("restoring writes a safety backup stamped with the injected instant")
    func safetyBackupCarriesTheInjectedTimestamp() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cvh-clock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configPath = root.appendingPathComponent(".swiftlint.yml")
        try "disabled_rules:\n  - force_try\n".write(to: configPath, atomically: true, encoding: .utf8)

        // An existing backup to restore from, named the way the service names them.
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        let earlier = Int(instant.timeIntervalSince1970) - 3_600
        let backupPath = root.appendingPathComponent(".swiftlint.yml.\(earlier).backup")
        try "opt_in_rules:\n  - force_unwrapping\n".write(to: backupPath, atomically: true, encoding: .utf8)

        let store = ConfigBackupStore(root: root.appendingPathComponent("store", isDirectory: true))
        let service = ConfigVersionHistoryService(now: .fixed(instant), backups: store)
        let backups = service.listBackups(for: configPath)
        let source = try #require(backups.first { Int($0.timestamp.timeIntervalSince1970) == earlier })

        try service.restoreBackup(source, to: configPath)

        let safety = service.listBackups(for: configPath)
            .first { Int($0.timestamp.timeIntervalSince1970) == Int(instant.timeIntervalSince1970) }
        #expect(safety != nil, "the safety backup should carry the instant the service was given")
        // It goes into the store, not beside the configuration.
        // (Directory listings spell the temporary folder as /private/var; compare resolved.)
        #expect(safety?.path.deletingLastPathComponent().resolvingSymlinksInPath()
            == store.directory(for: configPath).resolvingSymlinksInPath())
    }
}
