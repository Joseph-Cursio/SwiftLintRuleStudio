//
//  RuleAuditRunner.swift
//  SwiftLintRuleStudio
//
//  Runs one Rule Audit at a time, and lets only the current one report back.
//

import SwiftLintRuleStudioCore

/// Runs the Rule Audit for ``RuleAuditView``: one at a time, cancelled when superseded, when
/// the workspace changes, or when the view goes away.
///
/// An audit can run for minutes. One whose workspace closed, or that a new run replaced, must
/// not write its results back: they would land in the next workspace's audit, and "Enable All
/// Safe Rules" would turn on, in that workspace's config, rules measured safe in another one.
/// Cancelling also stops the lint in flight and removes its mirror.
@MainActor
final class RuleAuditRunner {
    private var task: Task<Void, Never>?
    private var generation = 0

    /// Whether an audit is running.
    var isRunning: Bool { task != nil }

    /// Runs `audit` for `workspace`, cancelling any audit already running.
    ///
    /// Progress and the outcome reach `onProgress` and `onFinish` only while the run is still
    /// the current one — not cancelled, not replaced, and with `workspace` still the one
    /// `currentWorkspace` reports. A cancelled run reports nothing at all.
    @discardableResult
    func start(
        for workspace: Workspace,
        currentWorkspace: @escaping () -> Workspace?,
        audit: @escaping (_ onProgress: @escaping (AuditProgress) -> Void) async throws -> RuleAuditView.AuditOutcome,
        onProgress: @escaping (AuditProgress) -> Void,
        onFinish: @escaping (Result<RuleAuditView.AuditOutcome, Error>) -> Void
    ) -> Task<Void, Never> {
        cancel()
        generation += 1
        let run = generation
        let isCurrent = { [weak self] in
            self?.generation == run && !Task.isCancelled && currentWorkspace()?.id == workspace.id
        }
        let task = Task {
            let result: Result<RuleAuditView.AuditOutcome, Error>
            do {
                result = .success(try await audit { progress in
                    if isCurrent() { onProgress(progress) }
                })
            } catch {
                result = .failure(error)
            }
            let reportsBack = isCurrent()
            if self.generation == run { self.task = nil }
            guard reportsBack else { return }
            if case .failure(let error) = result, error is CancellationError { return }
            onFinish(result)
        }
        self.task = task
        return task
    }

    /// Stops the running audit, if any; it reports nothing more.
    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
    }
}
