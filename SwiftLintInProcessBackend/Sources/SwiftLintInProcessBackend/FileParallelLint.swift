import Foundation
import struct SwiftLintCLISeam.LintProgress
import typealias SwiftLintCLISeam.LintProgressHandler
import SwiftLintFramework

/// Lints collected files side by side, each on the one thread that lints it.
///
/// SwiftLint lints a file by running its rules in parallel (`Array.parallelMap`, a
/// `DispatchQueue.concurrentPerform`), and every rule reads the file through SourceKitten's `File`,
/// which keeps its contents and string view behind two serial dispatch queues. Linted one file at a
/// time, every core worked on the same file, and its contents queue was contended hundreds of times
/// per file: a third of the lint's thread time went to waiting on it.
///
/// On macOS 27.2 such lints hang, once in tens to hundreds of thousands of files. Every thread waits
/// on one file's contents queue, none owns it, and the lint sits at 0% CPU for good. Read in a
/// reproduction, the queue's state was its idle value less exactly one drain — dispatch had released
/// it once more than it acquired it, in the contended handoff between waiters — so it read as
/// suspended, and every later `sync` waited for a resume that never comes. Uncontended, a `sync`
/// takes dispatch's fast path and never reaches that handoff.
///
/// `swiftlint` lints files concurrently, so a file's queues are rarely contended there. This goes
/// further: it lints files from a `concurrentPerform` at least as wide as the machine, and dispatch
/// divides a nested apply's threads by the outer apply's iteration count, so each file's rules run
/// on the thread linting that file and its queues are never contended at all. The cores stay busy
/// across files instead — which also means a workspace with fewer files than cores lints on fewer
/// threads, a single file on one.
enum FileParallelLint {

    /// The violations each of `linters` finds, in the order of `linters`. `progress` hears each
    /// file finish.
    static func styleViolations(
        of linters: [CollectedLinter],
        using storage: RuleStorage,
        workspacePath: URL,
        progress: LintProgressHandler
    ) -> [[StyleViolation]] {
        let work = Work(linters: linters, storage: storage)
        let results = Results(count: linters.count)
        forEachFile(count: linters.count) { index in
            // A file's work drains its own pool: one thread lints many files in one apply, and
            // dispatch drains no pool between them.
            let violations = autoreleasepool {
                // Task-locals don't reach dispatch's threads, and SwiftLint reads the working
                // directory from one.
                CurrentWorkingDirectory.$url.withValue(workspacePath) {
                    work.linters[index].styleViolations(using: work.storage)
                }
            }
            results.store(violations, at: index) { finished in
                progress(LintProgress(filesLinted: finished, totalFiles: work.linters.count))
            }
        }
        return results.inOrder
    }

    /// Runs `body` for each of `count` files, side by side, so that an apply `body` starts — as
    /// SwiftLint's over a file's rules — runs on the thread that started it.
    ///
    /// The apply is padded to at least the number of cores: dispatch gives a nested apply its
    /// maximum width divided by the outer apply's iteration count, which is then less than one
    /// thread. The extra iterations return at once.
    static func forEachFile(count: Int, _ body: @Sendable (Int) -> Void) {
        DispatchQueue.concurrentPerform(iterations: max(count, ProcessInfo.processInfo.activeProcessorCount)) { index in
            guard index < count else { return }
            body(index)
        }
    }

    /// What every thread reads. SwiftLint shares both across threads itself — `swiftlint` lints
    /// files concurrently with one storage — but declares neither `Sendable`.
    private final class Work: @unchecked Sendable {
        let linters: [CollectedLinter]
        let storage: RuleStorage

        init(linters: [CollectedLinter], storage: RuleStorage) {
            self.linters = linters
            self.storage = storage
        }
    }

    /// Each file's violations, stored as it finishes, and how many files have finished.
    final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var slots: [[StyleViolation]]
        private var finished = 0

        init(count: Int) {
            slots = Array(repeating: [], count: count)
        }

        /// Stores a file's violations and hands `report` the files finished so far, under the
        /// lock, so the counts arrive in order.
        func store(_ violations: [StyleViolation], at index: Int, report: (Int) -> Void) {
            lock.withLock {
                slots[index] = violations
                finished += 1
                report(finished)
            }
        }

        /// Each file's violations, in file order, whatever order the files finished in.
        var inOrder: [[StyleViolation]] {
            lock.withLock { slots }
        }
    }
}
