//
//  DiffCharacterizationPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for `YAMLConfigurationEngine.generateDiff(proposedConfig:)` —
//  the subject `swift-infer` proposes a `diff-disjointness` law for
//  (`Set(addedRules).isDisjoint(with: Set(removedRules))`, score 35).
//
//  Disjointness is what the tool can name; it is also the weakest law here, so
//  this suite states the full characterization the diff owes by being set algebra
//  over rule keys:
//
//      added    = keys(proposed) \ keys(current)
//      removed  = keys(current)  \ keys(proposed)
//      modified = { r ∈ keys(current) ∩ keys(proposed) : values differ }
//
//  Deliberately NOT a round-trip. `ConfigDiff` is lossy — it records rule-key
//  membership and a before/after string, but not the new rule *values*, and it
//  ignores included/excluded/reporter changes entirely. There is no
//  `apply(ConfigDiff, YAMLConfig)` in the codebase, so `apply(diff(a, b), a) == b`
//  is unsatisfiable as written rather than merely unwritten. The tool's own
//  caveat says the same thing.
//
//  Generators draw rule identifiers from a four-name alphabet so the two configs
//  overlap on most trials — a wide alphabet would make `added` and `removed`
//  everything and `modified` always empty, and the law would pass vacuously.
//
//  The generators emit plain primitives rather than `YAMLConfig` values: the
//  package builds under `.defaultIsolation(MainActor.self)`, so `YAMLConfig` is
//  main-actor-isolated and cannot be constructed inside a `Sendable` generator
//  closure. The configs are assembled in the test body, which is isolated.
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

/// A generated rule entry, kept isolation-free so it can cross the generator
/// boundary: an index into the shared name alphabet plus the two fields of a
/// `RuleConfiguration` that `generateDiff` can distinguish.
private struct RuleEntry: Sendable {
    let nameIndex: Int
    let enabled: Bool
    let severityIndex: Int
}

@MainActor
@Suite("generateDiff characterization property laws")
struct DiffCharacterizationPropertyLawTests {

    /// Rule identifiers shared by both sides. Four names, so two independently
    /// generated configs collide on most keys and `modified` is reachable.
    nonisolated static let ruleNames = ["line_length", "force_cast", "todo", "file_length"]

    /// The value space a rule configuration is drawn from — small enough that two
    /// configs sharing a key differ often, but not always, so both sides of
    /// "same key, same value ⇒ not modified" get exercised.
    nonisolated static let severities: [Severity?] = [nil, .warning, .error]

    /// 0–4 rule entries over the shared alphabet. Duplicate name indices are
    /// allowed and collapse on assembly — the last one wins, exactly as a
    /// repeated YAML key would.
    nonisolated private static func entriesGenerator()
    -> Generator<[RuleEntry], some SendableSequenceType> {
        let entry = zip(
            Gen<Int>.int(in: 0 ... (ruleNames.count - 1)),
            Gen<Bool>.bool,
            Gen<Int>.int(in: 0 ... (severities.count - 1))
        ).map { nameIndex, enabled, severityIndex in
            RuleEntry(nameIndex: nameIndex, enabled: enabled, severityIndex: severityIndex)
        }
        return entry.array(of: 0...4)
    }

    /// Assemble a config from generated entries. Only `rules` varies:
    /// `generateDiff` reads nothing else, and populating the unread fields would
    /// dilute the trials without adding reachable states.
    private func makeConfig(from entries: [RuleEntry]) -> YAMLConfigurationEngine.YAMLConfig {
        var config = YAMLConfigurationEngine.YAMLConfig()
        for entry in entries {
            config.rules[Self.ruleNames[entry.nameIndex]] = RuleConfiguration(
                enabled: entry.enabled,
                severity: Self.severities[entry.severityIndex]
            )
        }
        return config
    }

    private func makeEngine(
        current: YAMLConfigurationEngine.YAMLConfig
    ) -> YAMLConfigurationEngine {
        let engine = YAMLConfigurationEngine(
            configPath: URL(fileURLWithPath: "/nonexistent/.swiftlint.yml")
        )
        engine.updateConfig(current)
        return engine
    }

    @Test("generateDiff partitions rule keys: disjoint, exact, and sorted")
    func diffCharacterization() async {
        await propertyCheck(
            input: Self.entriesGenerator(),
            Self.entriesGenerator()
        ) { currentEntries, proposedEntries in
            let current = makeConfig(from: currentEntries)
            let proposed = makeConfig(from: proposedEntries)
            let diff = makeEngine(current: current).generateDiff(proposedConfig: proposed)

            let added = Set(diff.addedRules)
            let removed = Set(diff.removedRules)
            let modified = Set(diff.modifiedRules)
            let currentKeys = Set(current.rules.keys)
            let proposedKeys = Set(proposed.rules.keys)

            // Disjointness — the law swift-infer proposes. A key is added or
            // removed, never both; and neither is also "modified".
            #expect(added.isDisjoint(with: removed))
            #expect(added.isDisjoint(with: modified))
            #expect(removed.isDisjoint(with: modified))

            // Set algebra — the exact characterization disjointness only hints at.
            #expect(added == proposedKeys.subtracting(currentKeys))
            #expect(removed == currentKeys.subtracting(proposedKeys))
            #expect(modified == currentKeys.intersection(proposedKeys).filter {
                current.rules[$0] != proposed.rules[$0]
            })

            // Modified domain — a modification needs a key on both sides.
            #expect(modified.isSubset(of: currentKeys.intersection(proposedKeys)))

            // Sortedness — the arrays are ordered, and carry no duplicates.
            #expect(diff.addedRules == diff.addedRules.sorted())
            #expect(diff.removedRules == diff.removedRules.sorted())
            #expect(diff.modifiedRules == diff.modifiedRules.sorted())
            #expect(diff.addedRules.count == added.count)
            #expect(diff.removedRules.count == removed.count)
            #expect(diff.modifiedRules.count == modified.count)

            // hasChanges agrees with the three lists it summarizes.
            #expect(diff.hasChanges == !(added.isEmpty && removed.isEmpty && modified.isEmpty))
        }
    }

    @Test("diffing a config against itself reports no changes")
    func selfDiffIsEmpty() async {
        await propertyCheck(input: Self.entriesGenerator()) { entries in
            let config = makeConfig(from: entries)
            let diff = makeEngine(current: config).generateDiff(proposedConfig: config)

            #expect(diff.addedRules.isEmpty)
            #expect(diff.removedRules.isEmpty)
            #expect(diff.modifiedRules.isEmpty)
            #expect(diff.hasChanges == false)
        }
    }

    @Test("swapping the two configs swaps added and removed, and fixes modified")
    func swapSymmetry() async {
        await propertyCheck(
            input: Self.entriesGenerator(),
            Self.entriesGenerator()
        ) { currentEntries, proposedEntries in
            let current = makeConfig(from: currentEntries)
            let proposed = makeConfig(from: proposedEntries)
            let forward = makeEngine(current: current).generateDiff(proposedConfig: proposed)
            let backward = makeEngine(current: proposed).generateDiff(proposedConfig: current)

            #expect(forward.addedRules == backward.removedRules)
            #expect(forward.removedRules == backward.addedRules)
            #expect(forward.modifiedRules == backward.modifiedRules)
            #expect(forward.hasChanges == backward.hasChanges)
        }
    }
}
