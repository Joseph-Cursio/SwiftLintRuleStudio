//
//  DeterminismProvidersTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  The clock and the identifier source were read inline — `Date.now` and `UUID()` at the
//  point of use — which made the services that read them functions of the wall clock as
//  well as their arguments. Two runs disagreed, so nothing could be asserted about a
//  duration or a stamp, and a failing run could not be replayed.
//
//  These cover the providers themselves and the two behaviours that were unassertable
//  before them: an elapsed time, and a timestamp that round-trips through a filename.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@Suite("Determinism providers")
struct DeterminismProvidersTests {

    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - DateProvider

    @Test("a fixed provider returns the same instant every time")
    func fixedIsConstant() {
        let now = DateProvider.fixed(Self.epoch)
        #expect(now() == Self.epoch)
        #expect(now() == Self.epoch)
    }

    @Test("a scripted provider hands out its instants in order")
    func scriptedIsOrdered() {
        let now = DateProvider.scripted([Self.epoch, Self.epoch + 5, Self.epoch + 11])
        #expect(now() == Self.epoch)
        #expect(now() == Self.epoch + 5)
        #expect(now() == Self.epoch + 11)
    }

    @Test("a scripted provider repeats its last instant rather than trapping")
    func scriptedRepeatsTheLast() {
        // Deliberate: a caller that reads the clock one more time than the test predicted
        // gets a defensible answer instead of killing the test process. An assertion that
        // depended on the count still fails.
        let now = DateProvider.scripted([Self.epoch])
        #expect(now() == Self.epoch)
        #expect(now() == Self.epoch)
    }

    @Test("a scripted pair makes an elapsed time exactly what the test chose")
    func scriptedMakesDurationsAssertable() {
        // This is the shape every stopwatch in the codebase has: read the clock, do the
        // work, read it again, subtract. With the wall clock the difference is whatever the
        // machine was doing; scripted, it is a number the test picked.
        let now = DateProvider.scripted([Self.epoch, Self.epoch + 5])
        let startTime = now()
        let duration = now().timeIntervalSince(startTime)
        #expect(duration == 5)
    }

    @Test("the system provider actually reads the clock")
    func systemAdvances() {
        // Guards against a default that quietly froze — the failure mode that would make
        // every timestamp in production identical.
        let now = DateProvider.system
        let before = Date()
        let sampled = now()
        #expect(sampled.timeIntervalSince(before) >= 0)
        #expect(sampled.timeIntervalSince(before) < 60)
    }

    // MARK: - IDProvider

    @Test("sequential identifiers are the same on every run")
    func sequentialIsReproducible() {
        let first = IDProvider.sequential()
        let second = IDProvider.sequential()
        #expect(first() == second())
        #expect(first() == second())
    }

    @Test("sequential identifiers are distinct from each other")
    func sequentialIsUnique() {
        let makeID = IDProvider.sequential()
        let ids = (0..<50).map { _ in makeID() }
        #expect(Set(ids).count == 50)
    }

    @Test("random identifiers are the default and are not reproducible")
    func randomIsRandom() {
        let makeID = IDProvider.random
        #expect(makeID() != makeID())
    }
}

@Suite("Config version history — the backup timestamp round-trips")
struct ConfigVersionHistoryClockTests {

    /// A backup written at `t` is listed with timestamp `t`.
    ///
    /// The safety backup is named `{config}.{unix timestamp}.backup` and `listBackups` parses
    /// that stamp back out, so the clock is observable rather than incidental. With `Date.now`
    /// read inline there was nothing to compare the parsed value against; with the instant
    /// chosen, the encode/decode pair is a law.
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

        let service = ConfigVersionHistoryService(now: .fixed(instant))
        let backups = service.listBackups(for: configPath)
        let source = try #require(backups.first { Int($0.timestamp.timeIntervalSince1970) == earlier })

        try service.restoreBackup(source, to: configPath)

        let stamps = service.listBackups(for: configPath)
            .map { Int($0.timestamp.timeIntervalSince1970) }
        #expect(stamps.contains(Int(instant.timeIntervalSince1970)),
                "the safety backup should carry the instant the service was given, got \(stamps)")
    }
}
