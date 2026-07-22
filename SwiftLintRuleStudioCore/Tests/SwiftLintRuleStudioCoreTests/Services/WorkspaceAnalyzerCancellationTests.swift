//
//  WorkspaceAnalyzerCancellationTests.swift
//  SwiftLintRuleStudioTests
//
//  Regression for P3: analyze() stored its violations even after being superseded
//  (cancelled) by a newer run, because the task body never checked cancellation
//  before storeViolations — so a stale run overwrote the newer run's results.
//

import Foundation
import LintStudioCore
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

/// A one-shot gate: signals when a worker enters `wait()`, then blocks it until
/// `release()`. Deterministic — no sleeps.
private actor AnalysisGate {
    private var entered = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func awaitEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
struct WorkspaceAnalyzerCancellationTests {
    @Test("A superseded (cancelled) analysis does not store its violations")
    func cancelledAnalysisDoesNotStore() async throws {
        let storage = WorkspaceAnalyzerTestHelpers.createMockViolationStorage()
        let mockCLI = MockSwiftLintCLIActor()
        let gate = AnalysisGate()
        // Real violations — so a run that (buggily) stored after cancellation would
        // leave non-empty data, distinguishing the fix from "stored nothing anyway".
        let json = #"[{"file":"A.swift","line":1,"character":1,"severity":"warning","rule_id":"rule","reason":"m"}]"#
        await mockCLI.setLintCommandHandler { @Sendable _, _ in
            await gate.wait()
            return Data(json.utf8)
        }

        let analyzer = WorkspaceAnalyzer(
            swiftLintCLI: mockCLI,
            violationStorage: storage,
            fileTracker: FileTracker.createForTesting()
        )
        let workspace = Workspace(
            path: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )

        let analyzeTask = Task { try await analyzer.analyze(workspace: workspace) }
        await gate.awaitEntered()      // the analysis reached the lint call
        analyzer.cancelAnalysis()      // a newer run supersedes it
        await gate.release()           // let the lint call return its violations
        _ = try? await analyzeTask.value  // wait for the superseded run to finish

        #expect(storage.storedViolations.isEmpty, "a cancelled analysis must not overwrite storage")
    }
}
