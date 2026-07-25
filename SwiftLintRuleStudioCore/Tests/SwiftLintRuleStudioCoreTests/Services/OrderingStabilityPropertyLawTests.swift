//
//  OrderingStabilityPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for top-level key ordering — candidate §6.
//
//  `orderedTopLevelPairs(for:)` emits keys by: (1) `config.keyOrder`, preserving
//  the user's original file layout, (2) the reserved-key order for anything it
//  did not name, (3) everything else alphabetically. The hazard it exists to
//  defend against is that `config.rules` is a *dictionary* — unordered — so a
//  naive emission would reorder a user's `.swiftlint.yml` differently on
//  different runs, producing noisy diffs from an unchanged file.
//
//  Stated at the public boundary. `orderedTopLevelPairs` is `private` and stays
//  that way: the emitted order is readable through `parse(serialize(config))`,
//  whose `keyOrder` is recovered from the emitted text — so the laws bind
//  without widening anything. The roadmap listed §6 as blocked on visibility;
//  that came from `swift-infer` wanting to CALL the helper, which is not the
//  same as a law needing to.
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

private struct OrderingSpec: Sendable {
    /// Rule identifiers to configure, by index into `ruleNames`.
    let ruleIndices: [Int]
    /// Which reserved keys carry content.
    let setsExcluded: Bool
    let setsIncluded: Bool
    let setsReporter: Bool
    let setsDisabled: Bool
    /// Indices into `orderableKeys` naming an explicit `keyOrder` prefix.
    let keyOrderIndices: [Int]
}

@MainActor
@Suite("top-level ordering property laws")
struct OrderingStabilityPropertyLawTests {

    nonisolated private static let ruleNames = ["line_length", "todo", "force_cast", "empty_count"]
    /// The keys a generated config can name in `keyOrder`. Deliberately mixes
    /// reserved keys and rule keys, since those take different emission paths.
    nonisolated private static let orderableKeys = [
        "excluded", "included", "reporter", "disabled_rules", "line_length", "todo"
    ]

    nonisolated private static func specGenerator() -> Generator<OrderingSpec, some SendableSequenceType> {
        zip(
            Gen<Int>.int(in: 0 ... (ruleNames.count - 1)).array(of: 0...4),
            Gen<Bool>.bool,
            Gen<Bool>.bool,
            Gen<Bool>.bool,
            Gen<Bool>.bool,
            Gen<Int>.int(in: 0 ... (orderableKeys.count - 1)).array(of: 0...4)
        ).map { rules, excluded, included, reporter, disabled, keyOrder in
            OrderingSpec(
                ruleIndices: rules,
                setsExcluded: excluded,
                setsIncluded: included,
                setsReporter: reporter,
                setsDisabled: disabled,
                keyOrderIndices: keyOrder
            )
        }
    }

    // MARK: - Construction

    /// Build the config. `reversed` inserts the rule dictionary entries in the
    /// opposite order — the whole point of the permutation law, since a
    /// dictionary does not remember insertion order and must not leak it.
    private func makeConfig(
        from spec: OrderingSpec,
        reversed: Bool = false
    ) -> YAMLConfigurationEngine.YAMLConfig {
        var config = YAMLConfigurationEngine.YAMLConfig()
        let indices = reversed ? Array(spec.ruleIndices.reversed()) : spec.ruleIndices
        for index in indices {
            // Every rule carries a severity so it actually emits — a rule with
            // neither severity nor parameters emits nothing at all (see §1).
            config.rules[Self.ruleNames[index]] = RuleConfiguration(enabled: true, severity: .warning)
        }
        config.excluded = spec.setsExcluded ? ["Pods"] : nil
        config.included = spec.setsIncluded ? ["Sources"] : nil
        config.reporter = spec.setsReporter ? "json" : nil
        config.disabledRules = spec.setsDisabled ? ["force_cast"] : nil

        var order: [String] = []
        for index in spec.keyOrderIndices where !order.contains(Self.orderableKeys[index]) {
            order.append(Self.orderableKeys[index])
        }
        config.keyOrder = order
        return config
    }

    private func makeEngine() -> YAMLConfigurationEngine {
        YAMLConfigurationEngine(configPath: URL(fileURLWithPath: "/nonexistent/.swiftlint.yml"))
    }

    /// The top-level keys actually emitted, in order — recovered from the text
    /// by the parser, which is the only honest way to observe an emission.
    private func emittedOrder(_ config: YAMLConfigurationEngine.YAMLConfig) throws -> [String] {
        let engine = makeEngine()
        return try engine.parse(try engine.serialize(config)).keyOrder
    }

    // MARK: - Laws

    @Test("emitted order does not depend on dictionary insertion order")
    func insertionOrderDoesNotLeak() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let engine = makeEngine()
            let forward = try engine.serialize(makeConfig(from: spec))
            let backward = try engine.serialize(makeConfig(from: spec, reversed: true))

            // Byte-identical, not merely same-set: a user who changes nothing
            // must get a file that differs by nothing.
            #expect(forward == backward)
        }
    }

    @Test("keyOrder is honored as a relative order, for the keys that are emitted")
    func keyOrderIsHonored() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let config = makeConfig(from: spec)
            let emitted = try emittedOrder(config)

            // Only keys that survive emission can be ordered; `keyOrder` may name
            // keys the config no longer carries (a list emptied since load).
            let named = config.keyOrder.filter { emitted.contains($0) }
            #expect(Array(emitted.prefix(named.count)) == named)
        }
    }

    @Test("no key is emitted twice")
    func noDuplicateKeys() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let emitted = try emittedOrder(makeConfig(from: spec))
            #expect(emitted.count == Set(emitted).count)
        }
    }

    @Test("rule keys not named in keyOrder are emitted alphabetically")
    func unnamedRuleKeysSortAlphabetically() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let config = makeConfig(from: spec)
            let emitted = try emittedOrder(config)

            // The tail branch: whatever `keyOrder` and the reserved order did not
            // place is sorted, so output is stable rather than hash-dependent.
            let unnamedRules = emitted.filter {
                Self.ruleNames.contains($0) && !config.keyOrder.contains($0)
            }
            #expect(unnamedRules == unnamedRules.sorted())
        }
    }

    @Test("re-serializing a parsed config reproduces the same key order")
    func orderIsStableUnderReSerialization() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let engine = makeEngine()
            let config = makeConfig(from: spec)
            let once = try engine.parse(try engine.serialize(config))
            let twice = try engine.parse(try engine.serialize(once))

            // The order recovered from a file is the order that file is written
            // back in — the fixed point that keeps an untouched save a no-op.
            #expect(twice.keyOrder == once.keyOrder)
        }
    }
}
