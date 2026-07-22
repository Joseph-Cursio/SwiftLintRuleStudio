//
//  SupersededTaskGate.swift
//  SwiftLintRuleStudioTests
//
//  Shared gate for "superseded fire-and-forget task" regression tests. It makes
//  the first async arrival park until the test releases it, while later arrivals
//  pass straight through — so a test can deterministically drive the sequence
//  "start slow run → start fast run that supersedes it → release slow run" and
//  assert the slow run never overwrites the fast one's result.
//

/// A one-shot gate keyed on arrival order.
actor SupersededTaskGate {
    private var callIndex = 0
    private var firstEntered = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    /// Records an arrival and returns its zero-based index. The first arrival
    /// (index 0) parks until `release()`; every later arrival returns immediately.
    @discardableResult
    func arrive() async -> Int {
        let index = callIndex
        callIndex += 1
        if index == 0 {
            firstEntered = true
            enteredContinuation?.resume()
            enteredContinuation = nil
            await withCheckedContinuation { releaseContinuation = $0 }
        }
        return index
    }

    /// Suspends until the first arrival has parked in `arrive()`.
    func awaitFirstEntered() async {
        if firstEntered { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }

    /// Lets the parked first arrival resume.
    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
