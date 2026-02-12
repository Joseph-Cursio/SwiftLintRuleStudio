import Foundation

extension RuleRegistry {
    /// Start background loading for remaining rules
    func startBackgroundLoading(for rules: [Rule], startingIndex: Int) {
        if Self.isRunningTests {
            return
        }
        // Cancel any existing background loading task
        backgroundLoadingTask?.cancel()
        
        let rulesData = buildRulesData(from: rules, startingIndex: startingIndex)
        backgroundLoadingTask = Task { [swiftLintCLI] in
            await Self.runBackgroundBatches(
                rulesData: rulesData,
                swiftLintCLI: swiftLintCLI,
                update: { [weak self] index, rule in
                    await self?.updateRule(at: index, with: rule)
                }
            )
        }
    }

    private func updateRule(at index: Int, with rule: Rule) async {
        await MainActor.run { @Sendable [weak self] in
            guard let self, index < self.rules.count else { return }
            var updatedRules = self.rules
            updatedRules[index] = rule
            self.updateRules(updatedRules)
        }
    }

    private func buildRulesData(
        from rules: [Rule],
        startingIndex: Int
    ) -> [RuleBackgroundData] {
        var currentIndex = startingIndex
        return rules.map { rule in
            defer { currentIndex += 1 }
            return RuleBackgroundData(
                id: rule.id,
                category: rule.category,
                isOptIn: rule.isOptIn,
                index: currentIndex
            )
        }
    }
}

private extension RuleRegistry {
    struct RuleBackgroundData {
        let id: String
        let category: RuleCategory
        let isOptIn: Bool
        let index: Int
    }

    static func runBackgroundBatches(
        rulesData: [RuleBackgroundData],
        swiftLintCLI: SwiftLintCLIProtocol,
        update: @Sendable @escaping (Int, Rule) async -> Void
    ) async {
        let batchSize = 10
        for batchStart in stride(from: 0, to: rulesData.count, by: batchSize) {
            if Task.isCancelled {
                break
            }

            let batchEnd = min(batchStart + batchSize, rulesData.count)
            let batch = Array(rulesData[batchStart..<batchEnd])
            await loadBatch(
                batch,
                swiftLintCLI: swiftLintCLI,
                update: update
            )
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        print("✅ Background loading completed for \(rulesData.count) rules")
    }

    static func loadBatch(
        _ batch: [RuleBackgroundData],
        swiftLintCLI: SwiftLintCLIProtocol,
        update: @Sendable @escaping (Int, Rule) async -> Void
    ) async {
        do {
            try await withThrowingTaskGroup(of: (Int, Rule).self) { group in
                for data in batch {
                    group.addTask { @Sendable in
                        let rule = await fetchDetailedRule(
                            ruleId: data.id,
                            category: data.category,
                            isOptIn: data.isOptIn,
                            swiftLintCLI: swiftLintCLI
                        )
                        return (data.index, rule)
                    }
                }

                do {
                    for try await (index, detailedRule) in group {
                        await update(index, detailedRule)
                    }
                } catch {
                    print("⚠️ Error updating rules from background group: \(error.localizedDescription)")
                }
            }
        } catch {
            print("⚠️ Error during background batch loading: \(error.localizedDescription)")
        }
    }

    static func fetchDetailedRule(
        ruleId: String,
        category: RuleCategory,
        isOptIn: Bool,
        swiftLintCLI: SwiftLintCLIProtocol
    ) async -> Rule {
        do {
            let detailedRule = try await withTimeout(
                seconds: 30,
                ruleId: ruleId
            ) {
                try await fetchRuleDetailsHelper(
                    identifier: ruleId,
                    category: category,
                    isOptIn: isOptIn,
                    swiftLintCLI: swiftLintCLI
                )
            }
            return detailedRule
        } catch {
            print("⚠️ Background fetch failed for rule \(ruleId): \(error.localizedDescription)")
            return Rule(
                id: ruleId,
                name: ruleId,
                description: "No description available",
                category: category,
                isOptIn: isOptIn,
                parameters: nil,
                triggeringExamples: [],
                nonTriggeringExamples: [],
                documentation: nil
            )
        }
    }

    static func withTimeout<T: Sendable>(
        seconds: UInt64,
        ruleId: String,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                let message = "Rule detail fetch timed out for \(ruleId)"
                throw NSError(
                    domain: "RuleRegistry",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }

            guard let result = try await group.next() else {
                let message = "Rule detail fetch cancelled for \(ruleId)"
                throw NSError(
                    domain: "RuleRegistry",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }
            group.cancelAll()
            return result
        }
    }
}
