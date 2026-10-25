//
//  WorkspaceAnalyzerProgressTests.swift
//  SwiftLintRuleStudioTests
//
//  The Enabled Rule Violations screen shows how many files the lint has finished, which the
//  analyzer relays from the backend into `currentProgress`.
//

import Combine
import Foundation
import LintStudioCore
import SwiftLintCLISeam
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

/// A backend whose lint is a closure handed the lint's progress handler. It finds no violations.
private struct ReportingLintBackend: SwiftLintCLIProtocol {
    let lint: @Sendable (LintProgressHandler) async -> Void

    func executeLintCommand(
        configPath _: URL?,
        workspacePath _: URL,
        progress: @escaping LintProgressHandler
    ) async throws -> Data {
        await lint(progress)
        return Data("[]".utf8)
    }

    func executeLintCommand(configPath _: URL?, workspacePath _: URL) -> Data { Data("[]".utf8) }
    func detectSwiftLintPath() -> URL { URL(fileURLWithPath: "/usr/bin/true") }
    func executeRulesCommand() -> Data { Data() }
    func executeRuleDetailCommand(ruleId _: String) -> Data { Data() }
    func generateDocsForRule(ruleId _: String) -> String { "" }
    func getVersion() -> String { "0.0.0" }
}

/// Holds a lint mid-file until the test lets it go. Deterministic — no sleeps.
private actor LintGate {
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
struct WorkspaceAnalyzerProgressTests {
    private func makeAnalyzer(lint: @escaping @Sendable (LintProgressHandler) async -> Void) -> WorkspaceAnalyzer {
        WorkspaceAnalyzer(
            swiftLintCLI: ReportingLintBackend(lint: lint),
            violationStorage: WorkspaceAnalyzerTestHelpers.createMockViolationStorage(),
            fileTracker: FileTracker.createForTesting()
        )
    }

    private var workspace: Workspace {
        Workspace(path: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @Test("The backend's last file count reaches currentProgress before the analysis completes")
    func relaysFileProgress() async throws {
        let analyzer = makeAnalyzer { progress in
            for linted in 0...2 {
                progress(LintProgress(filesLinted: linted, totalFiles: 2))
            }
        }
        var published: [AnalysisProgress] = []
        let watch = analyzer.$currentProgress.compactMap(\.self).sink { published.append($0) }

        _ = try await analyzer.analyze(workspace: workspace)

        // Reports can coalesce, but the last one is always drawn before completion.
        let running = published.filter { !$0.isComplete }
        #expect(running.contains { $0.filesProcessed == 2 && $0.totalFiles == 2 })
        #expect(published.last?.isComplete == true)
        withExtendedLifetime(watch) {}
    }

    @Test("A superseded analysis's later file counts never reach currentProgress")
    func supersededRunStopsReporting() async throws {
        let gate = LintGate()
        let analyzer = makeAnalyzer { progress in
            progress(LintProgress(filesLinted: 1, totalFiles: 3))
            await gate.wait()
            // In-process, a superseded lint can't be stopped and keeps reporting.
            progress(LintProgress(filesLinted: 3, totalFiles: 3))
        }
        let target = workspace

        let analyzeTask = Task { try await analyzer.analyze(workspace: target) }
        await gate.awaitEntered()
        analyzer.cancelAnalysis()
        var afterCancel: [AnalysisProgress] = []
        let watch = analyzer.$currentProgress.dropFirst().compactMap(\.self).sink { afterCancel.append($0) }
        await gate.release()
        _ = try? await analyzeTask.value

        #expect(afterCancel.isEmpty, "a superseded run must not report into the next run's progress")
        #expect(analyzer.currentProgress == nil)
        withExtendedLifetime(watch) {}
    }
}
