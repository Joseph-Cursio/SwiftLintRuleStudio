import Foundation
import SwiftLintFramework
@testable import SwiftLintInProcessBackend
import Testing

/// Files are linted side by side, each by one thread, so no file's SourceKitten queues are
/// contended (see `FileParallelLint`).
@Suite("Linting files side by side")
struct FileParallelLintTests {

    /// The threads each file's inner apply ran on.
    private final class ThreadsSeen: @unchecked Sendable {
        private let lock = NSLock()
        private var threads: [Int: Set<UInt64>] = [:]

        func record(_ file: Int) {
            var id: UInt64 = 0
            pthread_threadid_np(nil, &id)
            lock.withLock { _ = threads[file, default: []].insert(id) }
        }

        var files: Int { lock.withLock { threads.count } }
        var mostPerFile: Int { lock.withLock { threads.values.map(\.count).max() ?? 0 } }
    }

    /// What the fix rests on: within the file loop, an apply — SwiftLint's parallel pass over a
    /// file's rules — runs on the thread that started it, however many files there are.
    @Test("Inside the file loop, an apply over a file's rules runs on one thread", arguments: [1, 3, 40])
    func nestedApplyRunsOnOneThread(files: Int) {
        let seen = ThreadsSeen()
        FileParallelLint.forEachFile(count: files) { file in
            DispatchQueue.concurrentPerform(iterations: 64) { _ in
                seen.record(file)
                usleep(200)
            }
        }
        #expect(seen.files == files)
        #expect(seen.mostPerFile == 1)
    }

    @Test("Violations come back in file order, whatever order the files finish in")
    func resultsKeepFileOrder() {
        let rule = RuleDescription(identifier: "test_rule", name: "Test Rule", description: "", kind: .lint)
        let violations = (0..<3).map { index in
            StyleViolation(
                ruleDescription: rule,
                location: Location(file: URL(fileURLWithPath: "/File\(index).swift"), line: 1),
                reason: "\(index)"
            )
        }
        let results = FileParallelLint.Results(count: 3)
        var reported: [Int] = []

        for index in [2, 0, 1] {
            results.store([violations[index]], at: index) { reported.append($0) }
        }

        #expect(results.inOrder.map { $0.map(\.reason) } == [["0"], ["1"], ["2"]])
        #expect(reported == [1, 2, 3])
    }

    @Test("Every file is linted, its violations are reported in file order, and progress counts up")
    func lintsEveryFileInOrder() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileParallelLintTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let names = (0..<30).map { String(format: "File%02d.swift", $0) }
        for name in names {
            try "let value: Any = 1\nlet cast = value as! Int\n"
                .write(to: workspace.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try "only_rules:\n  - force_cast\n"
            .write(to: workspace.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)

        let reports = ProgressRecorder()
        let data = try SwiftLintInProcessActor.lint(configPath: nil, workspacePath: workspace) {
            reports.record($0.filesLinted, of: $0.totalFiles)
        }

        let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let files = json.compactMap { ($0["file"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } }
        // The order SwiftLint lists the files in, as when they were linted one after another.
        let listed = try CurrentWorkingDirectory.$url.withValue(workspace) {
            try InProcessConfiguration.root(configPath: nil, workspacePath: workspace).configuration
                .lintableFiles(inPath: workspace, forceExclude: false, excludeByPrefix: false)
                .compactMap { $0.path?.lastPathComponent }
        }
        #expect(Set(listed) == Set(names))
        #expect(files == listed)
        #expect(json.allSatisfy { $0["rule_id"] as? String == "force_cast" })
        #expect(reports.snapshot.map(\.filesLinted) == Array(0...names.count))
        #expect(reports.snapshot.allSatisfy { $0.totalFiles == names.count })
    }
}
