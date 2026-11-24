//
//  TestTempDirectory.swift
//  SwiftLintRuleStudioTests
//

import Foundation

/// A self-cleaning root for test scratch directories under the system temp dir.
///
/// Scratch directories for tests, isolated per *process* so a cleanup can never
/// delete a directory another test is still using.
///
/// The previous design put every run's dirs directly in a shared
/// `$TMPDIR/SwiftLintRuleStudioTests` and, on first use, deleted everything
/// already in it. Its safety argument — "the purge only touches entries that
/// existed at process start, so directories created during this run are never
/// removed" — rested on two false premises:
///
///  1. **`static let` is lazy.** The initializer runs on first *access*, not at
///     process start. Under Swift Testing's parallel execution an arbitrary
///     amount of work has already happened by then, so "already there" routinely
///     meant "created seconds ago by a test that is still running."
///  2. **Not every helper routed through `make(_:)`.** Several app-target helpers
///     built `$TMPDIR/SwiftLintRuleStudioTests/<UUID>` themselves, landing in the
///     blast radius without ever calling in here.
///
/// The result was a live directory deleted mid-test, and the victim's next atomic
/// write failing with `ENOENT` — surfacing as *"Creating a temporary file via
/// mktemp failed"* reported at the test's declaration line, usually taking a whole
/// suite down at once. Measured at roughly one full-suite run in three.
///
/// Now each process gets its own `run-<pid>-<uuid>` root, so this run's cleanup
/// and another run's live directories cannot overlap. Leftovers from earlier runs
/// are still reclaimed, but only once they are `staleAfter` old — old enough that
/// no live process could still be using them.
///
/// `nonisolated` because the package sets `.defaultIsolation(MainActor.self)` and
/// there is nothing main-actor about creating a directory — helpers need to call
/// this from synchronous nonisolated contexts too. `root` is a `let` of a Sendable
/// type, and Swift guarantees its lazy initialization is run exactly once and
/// thread-safely.
nonisolated public enum TestTempDirectory {
    /// Age past which a leftover directory is considered abandoned. Comfortably
    /// longer than any full-suite run (~10s today), so a concurrently running
    /// process's directories are never eligible.
    private static let staleAfter: TimeInterval = 60 * 60

    private static let root: URL = {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudioTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        purgeStaleEntries(in: base)

        let processID = ProcessInfo.processInfo.processIdentifier
        let runRoot = base.appendingPathComponent(
            "run-\(processID)-\(UUID().uuidString)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)
        return runRoot
    }()

    /// Removes entries last modified more than `staleAfter` ago. Anything newer is
    /// left alone — that is the whole safety property, so do not "optimize" this
    /// into an unconditional sweep.
    private static func purgeStaleEntries(in base: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-staleAfter)
        for url in entries {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            guard let modified, modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Creates and returns a fresh, unique scratch directory inside this process's
    /// run root. `label` prefixes the directory name so leftover dirs are traceable
    /// to the helper that made them.
    public static func make(_ label: String = "t") -> URL {
        let dir = root.appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
