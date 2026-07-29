//
//  TestIsolationHelpers.swift
//  SwiftLintRuleStudioTests
//
//  Reusable helpers for test isolation using Swift Testing framework features
//

import Foundation
import LintStudioCore
@testable import SwiftLintRuleStudioCore
import Testing

/// Provides isolated UserDefaults instances for each test to prevent cross-test contamination
public enum IsolatedUserDefaults {
    /// Creates a unique UserDefaults suite for the current test
    /// Uses the test function name to ensure uniqueness
    public static func create(for testName: String) -> UserDefaults {
        // Use test name + UUID to ensure complete isolation
        let suiteName = "test.\(testName).\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create UserDefaults suite: \(suiteName)")
        }
        return userDefaults
    }

    /// Creates a shared UserDefaults suite for a test suite
    /// Useful when tests need to share state within a suite but isolate from others
    public static func createShared(for suiteName: String) -> UserDefaults {
        let fullSuiteName = "test.shared.\(suiteName)"
        guard let userDefaults = UserDefaults(suiteName: fullSuiteName) else {
            fatalError("Failed to create shared UserDefaults suite: \(fullSuiteName)")
        }
        return userDefaults
    }

    /// Cleans up a UserDefaults suite
    /// Note: UserDefaults doesn't expose suiteName, so we remove all keys manually
    public static func cleanup(_ userDefaults: UserDefaults) {
        // Remove all keys from the suite
        // We can't get the suite name directly, so we remove the onboarding key
        // In practice, each test uses a unique suite, so this is sufficient
        userDefaults.removeObject(forKey: "com.swiftlintrulestudio.hasCompletedOnboarding")
        // Remove any other test-specific keys if needed
        userDefaults.synchronize()
    }
}

// MARK: - Self-cleaning scratch directories

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

// MARK: - File marker (satisfies file_name lint rule)

private enum TestIsolationHelpers {}

// Helper to create DependencyContainer with isolated UserDefaults
public extension DependencyContainer {
    /// Creates a DependencyContainer with isolated UserDefaults for testing
    static func createForTesting(
        userDefaults: UserDefaults? = nil,
        ruleRegistry: RuleRegistry? = nil,
        swiftLintCLI: SwiftLintCLIProtocol? = nil,
        cacheManager: CacheManagerProtocol? = nil,
        violationStorage: ViolationStorageProtocol? = nil,
        workspaceManager: WorkspaceManager? = nil,
        onboardingManager: OnboardingManager? = nil,
        impactSimulator: (any ImpactSimulatorProtocol)? = nil
    ) -> DependencyContainer {
        // Create isolated UserDefaults if not provided
        let testUserDefaults = userDefaults
            ?? UserDefaults(suiteName: "test.DependencyContainer.\(UUID().uuidString)")
            ?? .standard

        // Create OnboardingManager with isolated UserDefaults if not provided
        let testOnboardingManager = onboardingManager ?? OnboardingManager(userDefaults: testUserDefaults)

        let testViolationStorage = violationStorage ?? (try? ViolationStorageActor(useInMemory: true))

        return DependencyContainer(
            ruleRegistry: ruleRegistry,
            swiftLintCLI: swiftLintCLI ?? MockSwiftLintCLIActor(),
            cacheManager: cacheManager,
            violationStorage: testViolationStorage,
            workspaceManager: workspaceManager,
            onboardingManager: testOnboardingManager,
            impactSimulator: impactSimulator,
            userDefaults: testUserDefaults
        )
    }
}

// Extension to OnboardingManager for test isolation
public extension OnboardingManager {
    /// Creates an OnboardingManager with isolated UserDefaults for testing
    static func createForTesting(testName: String) -> OnboardingManager {
        let userDefaults = IsolatedUserDefaults.create(for: testName)
        return OnboardingManager(userDefaults: userDefaults)
    }
}

// Extension to WorkspaceManager for test isolation
public extension WorkspaceManager {
    /// Creates a WorkspaceManager with isolated UserDefaults for testing
    /// Uses the test function name to ensure uniqueness
    static func createForTesting(testName: String) -> WorkspaceManager {
        let userDefaults = IsolatedUserDefaults.create(for: testName)
        return WorkspaceManager(userDefaults: userDefaults)
    }
}

// Extension to CacheManager for test isolation
public extension CacheManager {
    /// Creates a CacheManager with isolated cache directory for testing
    /// Uses UUID to ensure complete isolation between tests
    static func createForTesting() -> CacheManager {
        CacheManager(cacheDirectory: TestTempDirectory.make("cache"))
    }
}

// Extension to FileTracker for test isolation
public extension FileTracker {
    /// Creates a FileTracker with isolated cache file for testing
    /// Uses UUID to ensure complete isolation between tests
    /// Note: FileTracker is @MainActor, so this must be called from MainActor context
    @MainActor
    static func createForTesting() -> FileTracker {
        let cacheURL = TestTempDirectory.make("filetracker")
            .appendingPathComponent("file_tracker_cache.json")
        return FileTracker(cacheURL: cacheURL)
    }
}

// Note: Swift Testing framework provides isolation by default:
// 1. Each test gets a fresh struct instance (no shared state)
// 2. Tests run in parallel by default (helps identify isolation issues)
// 3. For sequential execution, you can use test arguments or organize tests into suites
//
// If you need sequential execution for specific tests, consider:
// - Using test arguments to control execution order
// - Organizing related tests into separate test files
// - Using shared isolated resources (like UserDefaults suites) when needed
