import Foundation

// swiftlint:disable function_body_length

extension RuleRegistry {
    /// Start background loading for remaining rules
    func startBackgroundLoading(for rules: [Rule], startingIndex: Int) {
        // Cancel any existing background loading task
        backgroundLoadingTask?.cancel()
        
        // Capture dependencies needed (nonisolated to avoid data race warnings)
        nonisolated(unsafe) let swiftLintCLICapture = self.swiftLintCLI
        
        // Capture weak reference to self for updates (accessed only from MainActor)
        nonisolated(unsafe) weak var weakSelf = self
        
        // Extract rules data before detached task to avoid capturing MainActor-isolated state
        let rulesData = rules.map { rule in
            (id: rule.id, category: rule.category, isOptIn: rule.isOptIn)
        }
        
        // Start new background task using Task.detached to avoid MainActor blocking
        backgroundLoadingTask = Task.detached { @Sendable in
            // Load rules in smaller batches to avoid overwhelming the system
            let batchSize = 10
            var currentIndex = startingIndex
            
            for batchStart in stride(from: 0, to: rulesData.count, by: batchSize) {
                // Check if task was cancelled
                if Task.isCancelled {
                    break
                }
                
                let batchEnd = min(batchStart + batchSize, rulesData.count)
                let batch = Array(rulesData[batchStart..<batchEnd])
                
                // Extract rule data to avoid capturing in closures
                let ruleData = batch.enumerated().map { offset, rule in
                    (id: rule.id, category: rule.category, isOptIn: rule.isOptIn, index: currentIndex + offset)
                }
                currentIndex += batch.count
                
                // Load batch in parallel
                do {
                    try await withThrowingTaskGroup(of: (Int, Rule).self) { group in
                        for data in ruleData {
                            let index = data.index
                            let ruleId = data.id
                            let category = data.category
                            let isOptIn = data.isOptIn
                            
                            group.addTask { @Sendable in
                                do {
                                    // Add timeout to prevent hanging (30 seconds per rule)
                                    let detailedRule = try await withThrowingTaskGroup(of: Rule.self) { timeoutGroup in
                                        // Start the actual fetch - helper can be called directly since it's not MainActor-isolated
                                        timeoutGroup.addTask { @Sendable in
                                            return try await Self.fetchRuleDetailsHelper(
                                                identifier: ruleId,
                                                category: category,
                                                isOptIn: isOptIn,
                                                swiftLintCLI: swiftLintCLICapture
                                            )
                                        }
                                        
                                        // Start timeout task
                                        timeoutGroup.addTask { @Sendable in
                                            try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                                            let message = "Rule detail fetch timed out for \(ruleId)"
                                            throw NSError(
                                                domain: "RuleRegistry",
                                                code: 3,
                                                userInfo: [NSLocalizedDescriptionKey: message]
                                            )
                                        }
                                        
                                        // Return first completed result (either success or timeout)
                                        guard let result = try await timeoutGroup.next() else {
                                            let message = "Rule detail fetch cancelled for \(ruleId)"
                                            throw NSError(
                                                domain: "RuleRegistry",
                                                code: 4,
                                                userInfo: [NSLocalizedDescriptionKey: message]
                                            )
                                        }
                                        timeoutGroup.cancelAll()
                                        return result
                                    }
                                    return (index, detailedRule)
                                } catch {
                                    // Return original rule if detail fetch fails or times out
                                    print("⚠️ Background fetch failed for rule \(ruleId): \(error.localizedDescription)")
                                    // Create a minimal rule as fallback
                                    let originalRule = Rule(
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
                                    return (index, originalRule)
                                }
                            }
                        }
                        
                        // Update rules as they complete - must be done on MainActor
                        do {
                            for try await (index, detailedRule) in group {
                                // Update on MainActor since rules is @Published
                                // Capture weakSelf again to avoid sending it across boundaries
                                nonisolated(unsafe) let capturedSelf = weakSelf
                                await MainActor.run { @Sendable in
                                    guard let self = capturedSelf, index < self.rules.count else { return }
                                    var updatedRules = self.rules
                                    updatedRules[index] = detailedRule
                                    self.updateRules(updatedRules)
                                }
                            }
                        } catch {
                            print("⚠️ Error updating rules from background group: \(error.localizedDescription)")
                        }
                    }
                } catch {
                    print("⚠️ Error during background batch loading: \(error.localizedDescription)")
                }
                
                // Small delay between batches to avoid overwhelming SwiftLint
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            print("✅ Background loading completed for \(rulesData.count) rules")
        }
    }
}
// swiftlint:enable function_body_length