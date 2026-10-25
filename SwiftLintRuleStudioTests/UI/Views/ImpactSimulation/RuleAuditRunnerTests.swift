//
//  RuleAuditRunnerTests.swift
//  SwiftLintRuleStudioTests
//
//  Only the current audit may write its results back. One that was cancelled — its workspace
//  closed or reopened, or the view left — or replaced, or whose workspace is no longer the
//  open one, reports nothing: its "safe" rules belong to another workspace.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
@Suite("RuleAuditRunner")
struct RuleAuditRunnerTests {

    /// An audit that reports progress, then waits until released, then reports again and
    /// returns an outcome — whether or not it was cancelled meanwhile, as a lint can't be
    /// interrupted midway.
    @MainActor
    private final class PendingAudit {
        private var release: CheckedContinuation<Void, Never>?
        private(set) var hasStarted = false
        private(set) var sawCancellation = false
        let outcome = RuleAuditView.AuditOutcome(entries: [], swiftFileCount: 7, duration: 1)

        func run(onProgress: @escaping (AuditProgress) -> Void) async throws -> RuleAuditView.AuditOutcome {
            hasStarted = true
            onProgress(AuditProgress(current: 1, total: 2, ruleId: "first"))
            await withCheckedContinuation { release = $0 }
            sawCancellation = Task.isCancelled
            onProgress(AuditProgress(current: 2, total: 2, ruleId: "second"))
            return outcome
        }

        func finish() {
            release?.resume()
            release = nil
        }

        func waitUntilStarted() async {
            while !hasStarted || release == nil { await Task.yield() }
        }
    }

    /// What a run reported.
    @MainActor
    private final class Reports {
        var progress: [Int] = []
        var finished: [Result<RuleAuditView.AuditOutcome, Error>] = []
    }

    private let workspace = Workspace(path: URL(fileURLWithPath: "/tmp/Audited"))

    @discardableResult
    private func start(
        _ runner: RuleAuditRunner,
        _ audit: PendingAudit,
        reports: Reports,
        current: @escaping () -> Workspace?
    ) -> Task<Void, Never> {
        runner.start(
            for: workspace,
            currentWorkspace: current,
            audit: { onProgress in try await audit.run(onProgress: onProgress) },
            onProgress: { reports.progress.append($0.current) },
            onFinish: { reports.finished.append($0) }
        )
    }

    @Test("A run that finishes reports its progress and outcome")
    func finishedRunReports() async {
        let runner = RuleAuditRunner()
        let audit = PendingAudit()
        let reports = Reports()

        let run = start(runner, audit, reports: reports) { workspace }
        await audit.waitUntilStarted()
        audit.finish()
        await run.value

        #expect(reports.progress == [1, 2])
        #expect(reports.finished.count == 1)
        #expect((try? reports.finished.first?.get().swiftFileCount) == 7)
        #expect(!runner.isRunning)
    }

    @Test("A cancelled run reports nothing more, though its audit returns anyway")
    func cancelledRunReportsNothing() async {
        // What a workspace change does — even reopening the same folder, which keeps its
        // workspace's identity — and what leaving the view does.
        let runner = RuleAuditRunner()
        let audit = PendingAudit()
        let reports = Reports()

        let run = start(runner, audit, reports: reports) { workspace }
        await audit.waitUntilStarted()
        runner.cancel()
        audit.finish()
        await run.value

        #expect(audit.sawCancellation, "the audit is cancelled, so the simulator stops and cleans up")
        #expect(reports.progress == [1], "no progress after the cancel")
        #expect(reports.finished.isEmpty)
        #expect(!runner.isRunning)
    }

    @Test("A run whose workspace is no longer the open one reports nothing")
    func runForAClosedWorkspaceReportsNothing() async {
        let runner = RuleAuditRunner()
        let audit = PendingAudit()
        let reports = Reports()
        var current: Workspace? = workspace

        let run = start(runner, audit, reports: reports) { current }
        await audit.waitUntilStarted()
        current = Workspace(path: URL(fileURLWithPath: "/tmp/Other"))
        audit.finish()
        await run.value

        #expect(reports.progress == [1])
        #expect(reports.finished.isEmpty)
    }

    @Test("Starting a run cancels the one before it, which reports nothing")
    func newRunSupersedesTheOld() async {
        let runner = RuleAuditRunner()
        let first = PendingAudit()
        let second = PendingAudit()
        let firstReports = Reports()
        let secondReports = Reports()

        let firstRun = start(runner, first, reports: firstReports) { workspace }
        await first.waitUntilStarted()
        let secondRun = start(runner, second, reports: secondReports) { workspace }
        await second.waitUntilStarted()
        first.finish()
        second.finish()
        await firstRun.value
        await secondRun.value

        #expect(first.sawCancellation)
        #expect(firstReports.finished.isEmpty)
        #expect(secondReports.finished.count == 1)
    }

    @Test("An audit that stops on cancellation isn't reported as a failure")
    func cancellationIsNotAFailure() async {
        let runner = RuleAuditRunner()
        let reports = Reports()

        let run = runner.start(
            for: workspace,
            currentWorkspace: { workspace },
            audit: { _ in throw CancellationError() },
            onProgress: { _ in },
            onFinish: { reports.finished.append($0) }
        )
        await run.value

        #expect(reports.finished.isEmpty)
    }

    @Test("A failed audit reports its error")
    func failedAuditReportsItsError() async {
        struct AuditFailure: Error {}
        let runner = RuleAuditRunner()
        let reports = Reports()

        let run = runner.start(
            for: workspace,
            currentWorkspace: { workspace },
            audit: { _ in throw AuditFailure() },
            onProgress: { _ in },
            onFinish: { reports.finished.append($0) }
        )
        await run.value

        #expect(reports.finished.count == 1)
        if case .failure(let error)? = reports.finished.first {
            #expect(error is AuditFailure)
        } else {
            Issue.record("expected the failure to be reported")
        }
    }
}
