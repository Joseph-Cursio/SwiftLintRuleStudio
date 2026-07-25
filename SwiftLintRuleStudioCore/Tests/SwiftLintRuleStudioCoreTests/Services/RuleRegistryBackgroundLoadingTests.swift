//
//  RuleRegistryBackgroundLoadingTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for RuleRegistry+BackgroundLoading internal helpers.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

/// Actor that records (index, ruleId) tuples seen by the background-loading update callback.
private actor UpdateRecorder {
    private(set) var updates: [(Int, String)] = []

    func append(_ index: Int, _ ruleId: String) {
        updates.append((index, ruleId))
    }

    func snapshot() -> [(Int, String)] {
        updates
    }

    func count() -> Int {
        updates.count
    }
}

/// Actor that records how many CLI calls were in flight simultaneously.
///
/// Concurrency is what "runs in parallel" actually means, and unlike elapsed
/// time it does not depend on how busy the machine is. Every handler brackets
/// its work with `enter()` / `leave()`; `peak` is the high-water mark.
private actor ConcurrencyTracker {
    private var inFlight = 0
    private(set) var peak = 0

    func enter() {
        inFlight += 1
        peak = max(peak, inFlight)
    }

    func leave() {
        inFlight -= 1
    }
}

/// Build a fake rule details body the parser will accept (`Name (id): description`)
/// with non-empty triggering and non-triggering example sections.
nonisolated private func makeDetailsBody(ruleId: String) -> String {
    """
    Detailed \(ruleId) (\(ruleId)): detailed-desc-\(ruleId)

    Triggering Examples (violations are marked with '↓'):
        let bad = NSNumber() ↓as! Int

    Non-Triggering Examples:
        if let value = NSNumber() as? Int { _ = value }

    Configuration:
    """
}

/// Build empty markdown docs so populateFromDocs leaves examples empty and we fall through
/// to populateFromRuleDetails.
nonisolated private func emptyDocs(forRuleId _: String) -> String { "" }

/// Build a batch of N rules suitable for runBackgroundBatches/loadBatch.
nonisolated private func makeBackgroundBatch(count: Int, startingIndex: Int = 0) -> [RuleRegistry.RuleBackgroundData] {
    (0..<count).map { offset in
        RuleRegistry.RuleBackgroundData(
            id: "rule_\(offset)",
            category: .style,
            isOptIn: false,
            isAnalyzer: false,
            usesSourceKit: false,
            index: startingIndex + offset
        )
    }
}

struct RuleRegistryBackgroundLoadingTests {
    @Test("runBackgroundBatches happy path invokes update for every rule with merged details")
    func runBackgroundBatchesHappyPath() async throws {
        let mockCLI = MockSwiftLintCLIActor()
        await mockCLI.setGenerateDocsHandler { ruleId in emptyDocs(forRuleId: ruleId) }
        await mockCLI.setRuleDetailCommandHandler { ruleId in
            Data(makeDetailsBody(ruleId: ruleId).utf8)
        }

        let rulesData = makeBackgroundBatch(count: 15, startingIndex: 100)
        let recorder = UpdateRecorder()

        await RuleRegistry.runBackgroundBatches(
            rulesData: rulesData,
            swiftLintCLI: mockCLI
        ) { index, rule in
            await recorder.append(index, rule.id)
        }

        let snapshot = await recorder.snapshot()
        try #require(snapshot.count == 15, "Expected one update per rule")

        let observedIndices = Set(snapshot.map(\.0))
        let expectedIndices = Set(100..<115)
        #expect(observedIndices == expectedIndices, "startingIndex offset must be preserved")

        // Each rule id reported should map back to a rule with detailed description merged.
        // Re-fetch one rule via fetchDetailedRule to assert the merge path was used.
        let probe = await RuleRegistry.fetchDetailedRule(
            ruleId: "rule_3",
            category: .style,
            isOptIn: false,
            swiftLintCLI: mockCLI
        )
        #expect(probe.description.contains("detailed-desc-rule_3"))
        #expect(probe.triggeringExamples.isEmpty == false)
        #expect(probe.nonTriggeringExamples.isEmpty == false)
    }

    @Test("runBackgroundBatches respects Task.isCancelled between batches")
    func runBackgroundBatchesCancellation() async throws {
        let mockCLI = MockSwiftLintCLIActor()
        await mockCLI.setGenerateDocsHandler { ruleId in emptyDocs(forRuleId: ruleId) }
        await mockCLI.setRuleDetailCommandHandler { ruleId in
            // Each call is slow enough that batch 2 is still running when we cancel.
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            return Data(makeDetailsBody(ruleId: ruleId).utf8)
        }

        // 25 rules => 3 batches (10 + 10 + 5)
        let rulesData = makeBackgroundBatch(count: 25)
        let recorder = UpdateRecorder()

        let work = Task {
            await RuleRegistry.runBackgroundBatches(
                rulesData: rulesData,
                swiftLintCLI: mockCLI
            ) { index, rule in
                await recorder.append(index, rule.id)
            }
        }

        // Batch 1 takes ~200ms (10 parallel * 200ms), then 100ms sleep, then batch 2 begins.
        // Cancel at 400ms — first batch is done, second batch (or the gap) is in flight.
        try await Task.sleep(nanoseconds: 400_000_000) // 400ms
        work.cancel()
        _ = await work.value

        let total = await recorder.count()
        #expect(total < 25, "Cancellation should stop subsequent batches; observed \(total) updates")
        #expect(total > 0, "First batch should have completed before cancellation; observed \(total)")
    }

    @Test("runBackgroundBatches with empty input fires no updates and does not crash")
    func runBackgroundBatchesEmpty() async {
        let mockCLI = MockSwiftLintCLIActor()
        let recorder = UpdateRecorder()

        await RuleRegistry.runBackgroundBatches(
            rulesData: [],
            swiftLintCLI: mockCLI
        ) { index, rule in
            await recorder.append(index, rule.id)
        }

        let count = await recorder.count()
        #expect(count == 0)
    }

    @Test("loadBatch runs its rules concurrently, not one after another")
    func loadBatchRunsInParallel() async throws {
        // This used to assert `elapsed < 5 × the per-call delay`, which made a
        // structural property depend on how loaded the machine was — it failed at
        // 1.16s against a 1.0s budget while another build was running, and would
        // be worse on a shared CI runner. Elapsed time was only ever a proxy;
        // the property is that the calls OVERLAP, so measure that directly.
        let mockCLI = MockSwiftLintCLIActor()
        let tracker = ConcurrencyTracker()
        await mockCLI.setGenerateDocsHandler { ruleId in emptyDocs(forRuleId: ruleId) }
        await mockCLI.setRuleDetailCommandHandler { ruleId in
            await tracker.enter()
            // Hold the slot long enough that every sibling call has started
            // before any of them finishes. This is not a timing assertion: the
            // sleep only has to outlast spawning ten tasks, which is microseconds,
            // so the margin here is ~1000× rather than the old 5×.
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            await tracker.leave()
            return Data(makeDetailsBody(ruleId: ruleId).utf8)
        }

        let batch = makeBackgroundBatch(count: 10)
        let recorder = UpdateRecorder()

        await RuleRegistry.loadBatch(
            batch,
            swiftLintCLI: mockCLI
        ) { index, rule in
            await recorder.append(index, rule.id)
        }

        #expect(await recorder.count() == 10)

        // `loadBatch` adds every rule to one unbounded TaskGroup, so all ten are
        // in flight together. Sequential execution would peak at 1. If a
        // concurrency cap is ever introduced deliberately, this is the test that
        // should be updated to the new bound.
        let peak = await tracker.peak
        #expect(peak == 10, "Expected all ten calls in flight at once; peak was \(peak)")
    }

    @Test("fetchDetailedRule success path returns merged details from CLI")
    func fetchDetailedRuleSuccess() async {
        let mockCLI = MockSwiftLintCLIActor()
        await mockCLI.setGenerateDocsHandler { ruleId in emptyDocs(forRuleId: ruleId) }
        await mockCLI.setRuleDetailCommandHandler { ruleId in
            Data(makeDetailsBody(ruleId: ruleId).utf8)
        }

        let rule = await RuleRegistry.fetchDetailedRule(
            ruleId: "my_rule",
            category: .lint,
            isOptIn: true,
            swiftLintCLI: mockCLI
        )

        #expect(rule.id == "my_rule")
        #expect(rule.category == .lint)
        #expect(rule.isOptIn == true)
        #expect(rule.description == "detailed-desc-my_rule")
        #expect(rule.triggeringExamples.isEmpty == false)
        #expect(rule.nonTriggeringExamples.isEmpty == false)
        #expect(rule.description != "No description available")
    }

    @Test("fetchDetailedRule returns fallback Rule when CLI throws")
    func fetchDetailedRuleFallback() async {
        let mockCLI = MockSwiftLintCLIActor(shouldFail: true)

        let rule = await RuleRegistry.fetchDetailedRule(
            ruleId: "failing_rule",
            category: .performance,
            isOptIn: true,
            swiftLintCLI: mockCLI
        )

        #expect(rule.id == "failing_rule")
        #expect(rule.name == "failing_rule")
        #expect(rule.description == "No description available")
        #expect(rule.category == .performance)
        #expect(rule.isOptIn == true)
        #expect(rule.triggeringExamples.isEmpty)
        #expect(rule.nonTriggeringExamples.isEmpty)
    }

    @Test("withTimeout returns the operation result when it completes in time")
    func withTimeoutReturnsResult() async throws {
        let value = try await RuleRegistry.withTimeout(
            seconds: 5,
            ruleId: "quick_rule"
        ) {
            42
        }
        #expect(value == 42)
    }

    @Test("withTimeout throws NSError with RuleRegistry/3 when operation exceeds timeout")
    func withTimeoutThrowsOnTimeout() async {
        do {
            _ = try await RuleRegistry.withTimeout(
                seconds: 1,
                ruleId: "slow_rule"
            ) {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                return 0
            }
            Issue.record("Expected timeout error to be thrown")
        } catch let error as NSError {
            #expect(error.domain == "RuleRegistry")
            #expect(error.code == 3)
            let message = error.localizedDescription
            #expect(message.contains("slow_rule"))
        } catch {
            Issue.record("Expected NSError, got \(error)")
        }
    }

    @Test("buildRulesData preserves startingIndex offset and rule metadata")
    @MainActor
    func buildRulesDataIndexCounter() {
        let mockCLI = MockSwiftLintCLIActor()
        let cache = MockCacheManager()
        let registry = RuleRegistry(swiftLintCLI: mockCLI, cacheManager: cache)

        let inputs: [Rule] = [
            Rule(id: "alpha", name: "Alpha", description: "", category: .style, isOptIn: false),
            Rule(id: "beta", name: "Beta", description: "", category: .lint, isOptIn: true),
            Rule(
                id: "gamma",
                name: "Gamma",
                description: "",
                category: .metrics,
                isOptIn: true,
                isAnalyzer: true
            )
        ]

        let result = registry.buildRulesData(from: inputs, startingIndex: 5)

        #expect(result.count == 3)
        #expect(result.map(\.index) == [5, 6, 7])
        #expect(result.map(\.id) == ["alpha", "beta", "gamma"])
        #expect(result.map(\.category) == [.style, .lint, .metrics])
        #expect(result.map(\.isOptIn) == [false, true, true])
        #expect(result.map(\.isAnalyzer) == [false, false, true])
    }

    @Test("fetchDetailedRule preserves isAnalyzer flag through happy path")
    func fetchDetailedRulePreservesAnalyzerFlag() async {
        let mockCLI = MockSwiftLintCLIActor()
        await mockCLI.setGenerateDocsHandler { ruleId in emptyDocs(forRuleId: ruleId) }
        await mockCLI.setRuleDetailCommandHandler { ruleId in
            Data(makeDetailsBody(ruleId: ruleId).utf8)
        }

        let rule = await RuleRegistry.fetchDetailedRule(
            ruleId: "capture_variable",
            category: .lint,
            isOptIn: true,
            swiftLintCLI: mockCLI,
            isAnalyzer: true
        )

        #expect(rule.isAnalyzer == true)
        #expect(rule.isOptIn == true)
    }

    @Test("fetchDetailedRule preserves isAnalyzer flag through fallback path")
    func fetchDetailedRuleFallbackPreservesAnalyzerFlag() async {
        let mockCLI = MockSwiftLintCLIActor(shouldFail: true)

        let rule = await RuleRegistry.fetchDetailedRule(
            ruleId: "unused_import",
            category: .lint,
            isOptIn: true,
            swiftLintCLI: mockCLI,
            isAnalyzer: true
        )

        #expect(rule.isAnalyzer == true)
        #expect(rule.isOptIn == true)
    }
}
