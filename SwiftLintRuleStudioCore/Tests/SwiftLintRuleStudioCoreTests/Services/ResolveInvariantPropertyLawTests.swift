//
//  ResolveInvariantPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for `ResolvedConfigurationEngine.resolve(at:in:)` — candidate §5.
//
//  The fold is order-sensitive by design (deeper-wins) and `mergeRootOnlyKeys`
//  treats the root specially, so `(a⊕b)⊕c` vs `a⊕(b⊕c)` is not the right frame
//  and associativity is not chased here. What the fold owes is an *invariant*:
//  `mergeMembership` removes a rule from the opposite set before inserting it,
//  so a rule must never end up both disabled and opted in.
//
//  Generators build a linear three-layer chain (/ws → /ws/a → /ws/a/b). A rule
//  alphabet of three keeps the layers colliding on most trials — the interesting
//  cases are where a deeper layer contradicts a shallower one, and a wide
//  alphabet would almost never produce that.
//
//  Layers are allowed to contradict *themselves* too — a rule can be generated
//  into both `disabled_rules` and `opt_in_rules` of the same config — so the
//  invariant below is unconditional rather than true only of well-formed input.
//  SwiftLint resolves that contradiction in favour of disabled (verified against
//  0.65.0; see `mergeMembership`), and `sameLayerContradictionResolvesToDisabled`
//  pins that tie-break directly.
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

/// One generated layer, kept to primitives so it can cross the generator
/// boundary — `YAMLConfig` is main-actor-isolated and cannot be built inside a
/// `Sendable` closure.
private struct LayerSpec: Sendable {
    /// Per rule: 0 = unmentioned, 1 = disabled, 2 = opted in, 3 = listed in BOTH
    /// keys of the same config — the self-contradiction SwiftLint resolves as
    /// disabled.
    let membership: [Int]
    /// Per rule: 0 = not configured, 1 = warning, 2 = error.
    let configures: [Int]
    /// Whether this layer sets `excluded` / `included` / `reporter`.
    let setsRootOnlyKeys: Bool
}

@MainActor
@Suite("resolve invariant property laws")
struct ResolveInvariantPropertyLawTests {

    nonisolated private static let ruleNames = ["todo", "force_cast", "line_length"]
    nonisolated private static let layerCount = 3
    nonisolated private static let root = URL(fileURLWithPath: "/ws")

    /// `/ws`, `/ws/a`, `/ws/a/b` — a linear chain, so every layer applies to the
    /// deepest target and `layerChain` is the whole tree in depth order.
    nonisolated private static var directories: [URL] {
        [root, root.appendingPathComponent("a"), root.appendingPathComponent("a/b")]
    }

    nonisolated private static func layerSpecsGenerator()
    -> Generator<[LayerSpec], some SendableSequenceType> {
        // Membership spans 0...3 so a layer can list a rule in both keys;
        // `configures` only needs 0...2 (unset / warning / error).
        let spec = zip(
            Gen<Int>.int(in: 0...3).array(of: ruleNames.count ... ruleNames.count),
            Gen<Int>.int(in: 0...2).array(of: ruleNames.count ... ruleNames.count),
            Gen<Bool>.bool
        ).map { membership, configures, setsRootOnlyKeys in
            LayerSpec(membership: membership, configures: configures, setsRootOnlyKeys: setsRootOnlyKeys)
        }
        return spec.array(of: layerCount ... layerCount)
    }

    // MARK: - Construction

    private func makeConfig(from spec: LayerSpec) -> YAMLConfigurationEngine.YAMLConfig {
        var config = YAMLConfigurationEngine.YAMLConfig()
        var disabled: [String] = []
        var optIn: [String] = []

        for (index, name) in Self.ruleNames.enumerated() {
            switch spec.membership[index] {
            case 1: disabled.append(name)
            case 2: optIn.append(name)
            case 3: disabled.append(name); optIn.append(name)
            default: break
            }
            if spec.configures[index] != 0 {
                config.rules[name] = RuleConfiguration(
                    enabled: true,
                    severity: spec.configures[index] == 1 ? .warning : .error
                )
            }
        }

        config.disabledRules = disabled.isEmpty ? nil : disabled
        config.optInRules = optIn.isEmpty ? nil : optIn
        if spec.setsRootOnlyKeys {
            config.excluded = ["Pods"]
            config.included = ["Sources"]
            config.reporter = "json"
        }
        return config
    }

    private func makeDiscovered(
        directory: URL,
        depth: Int,
        config: YAMLConfigurationEngine.YAMLConfig?
    ) -> DiscoveredConfig {
        DiscoveredConfig(
            id: UUID(),
            configPath: directory.appendingPathComponent(".swiftlint.yml"),
            directoryPath: directory,
            relativePath: depth == 0 ? ".swiftlint.yml" : "a/.swiftlint.yml",
            depth: depth,
            isRoot: depth == 0,
            parentID: nil,
            config: config,
            parseError: nil,
            summary: ConfigSummary(
                disabledRuleCount: 0,
                optInRuleCount: 0,
                analyzerRuleCount: 0,
                configuredRuleCount: 0,
                onlyRules: nil,
                setsExcluded: false,
                setsIncluded: false,
                setsReporter: false
            )
        )
    }

    private func makeTree(from specs: [LayerSpec]) -> ConfigTree {
        let configs = specs.enumerated().map { depth, spec in
            makeDiscovered(directory: Self.directories[depth], depth: depth, config: makeConfig(from: spec))
        }
        return ConfigTree(workspaceRoot: Self.root, configs: configs)
    }

    /// The deepest layer index whose `selector` is non-zero, or nil.
    nonisolated private static func deepestLayer(
        _ specs: [LayerSpec],
        where selector: (LayerSpec) -> Int
    ) -> Int? {
        specs.indices.reversed().first { selector(specs[$0]) != 0 }
    }

    // MARK: - The invariant

    @Test("a rule is never both disabled and opted in")
    func mutualExclusionInvariant() async {
        await propertyCheck(input: Self.layerSpecsGenerator()) { specs in
            let resolved = ResolvedConfigurationEngine()
                .resolve(at: Self.directories[Self.layerCount - 1], in: makeTree(from: specs))

            let disabled = Set(resolved.disabledRules.map(\.identifier))
            let optedIn = Set(resolved.optInRules.map(\.identifier))
            #expect(disabled.isDisjoint(with: optedIn))
        }
    }

    @Test("the deepest layer that mentions a rule decides its membership and owns the attribution")
    func deepestMentionWins() async {
        await propertyCheck(input: Self.layerSpecsGenerator()) { specs in
            let tree = makeTree(from: specs)
            let resolved = ResolvedConfigurationEngine()
                .resolve(at: Self.directories[Self.layerCount - 1], in: tree)

            let disabled = Dictionary(
                uniqueKeysWithValues: resolved.disabledRules.map { ($0.identifier, $0.setBy) }
            )
            let optedIn = Dictionary(
                uniqueKeysWithValues: resolved.optInRules.map { ($0.identifier, $0.setBy) }
            )

            for (index, name) in Self.ruleNames.enumerated() {
                let deepest = Self.deepestLayer(specs) { $0.membership[index] }
                guard let deepest else {
                    // Unmentioned everywhere ⇒ absent from both sets.
                    #expect(disabled[name] == nil)
                    #expect(optedIn[name] == nil)
                    continue
                }
                // 1 = disabled, 3 = listed in both and therefore disabled;
                // 2 = opted in.
                if specs[deepest].membership[index] == 2 {
                    #expect(optedIn[name]?.depth == deepest)
                    #expect(disabled[name] == nil)
                } else {
                    #expect(disabled[name]?.depth == deepest)
                    #expect(optedIn[name] == nil)
                }
            }
        }
    }

    @Test("rule configurations are deeper-wins, and keep the next-deepest as history")
    func ruleConfigurationsAreDeeperWins() async {
        await propertyCheck(input: Self.layerSpecsGenerator()) { specs in
            let resolved = ResolvedConfigurationEngine()
                .resolve(at: Self.directories[Self.layerCount - 1], in: makeTree(from: specs))
            let byIdentifier = Dictionary(
                uniqueKeysWithValues: resolved.ruleConfigurations.map { ($0.identifier, $0) }
            )

            for (index, name) in Self.ruleNames.enumerated() {
                let setters = specs.indices.filter { specs[$0].configures[index] != 0 }
                guard let deepest = setters.last else {
                    #expect(byIdentifier[name] == nil)
                    continue
                }
                let entry = byIdentifier[name]
                #expect(entry?.setBy.depth == deepest)

                // The override history is the next-deepest setter, and only that.
                let previous = setters.dropLast().last
                #expect(entry?.previousSetBy?.depth == previous)
                #expect((entry?.previousConfiguration == nil) == (previous == nil))
            }

            // Sorted by identifier, as the accumulator promises.
            #expect(
                resolved.ruleConfigurations.map(\.identifier)
                    == resolved.ruleConfigurations.map(\.identifier).sorted()
            )
        }
    }

    @Test("excluded, included and reporter are honored only from the root layer")
    func rootOnlyKeysIgnoreNestedLayers() async {
        await propertyCheck(input: Self.layerSpecsGenerator()) { specs in
            let resolved = ResolvedConfigurationEngine()
                .resolve(at: Self.directories[Self.layerCount - 1], in: makeTree(from: specs))

            // Present exactly when the ROOT sets them — a nested layer setting the
            // same keys contributes nothing, however deep it is.
            let rootSets = specs[0].setsRootOnlyKeys
            #expect((resolved.excluded != nil) == rootSets)
            #expect((resolved.included != nil) == rootSets)
            #expect((resolved.reporter != nil) == rootSets)

            // And when present they are always attributed to the root.
            #expect(resolved.excluded.map(\.setBy.isRoot) ?? true)
            #expect(resolved.included.map(\.setBy.isRoot) ?? true)
            #expect(resolved.reporter.map(\.setBy.isRoot) ?? true)
        }
    }

    @Test("every attribution names a layer that is actually in the chain")
    func attributionsComeFromTheChain() async {
        await propertyCheck(input: Self.layerSpecsGenerator()) { specs in
            let resolved = ResolvedConfigurationEngine()
                .resolve(at: Self.directories[Self.layerCount - 1], in: makeTree(from: specs))
            let chainIDs = Set(resolved.layerChain.map(\.id))

            for decision in resolved.disabledRules + resolved.optInRules + resolved.analyzerRules {
                #expect(chainIDs.contains(decision.setBy.id))
            }
            for configuration in resolved.ruleConfigurations {
                #expect(chainIDs.contains(configuration.setBy.id))
                if let previous = configuration.previousSetBy {
                    #expect(chainIDs.contains(previous.id))
                }
            }
            for identifier in [resolved.excluded?.setBy.id, resolved.included?.setBy.id, resolved.reporter?.setBy.id] {
                if let identifier { #expect(chainIDs.contains(identifier)) }
            }
        }
    }

    // MARK: - Identity

    @Test("an empty tree resolves to an empty configuration")
    func emptyTreeIsIdentity() {
        let resolved = ResolvedConfigurationEngine()
            .resolve(at: Self.root, in: ConfigTree(workspaceRoot: Self.root, configs: []))

        #expect(resolved.layerChain.isEmpty)
        #expect(resolved.disabledRules.isEmpty)
        #expect(resolved.optInRules.isEmpty)
        #expect(resolved.analyzerRules.isEmpty)
        #expect(resolved.ruleConfigurations.isEmpty)
        #expect(resolved.onlyRules == nil)
        #expect(resolved.excluded == nil)
        #expect(resolved.included == nil)
        #expect(resolved.reporter == nil)
    }

    @Test("a chain of configs that set nothing resolves to no decisions")
    func emptyConfigsContributeNothing() {
        let specs = (0 ..< Self.layerCount).map { _ in
            LayerSpec(
                membership: Array(repeating: 0, count: Self.ruleNames.count),
                configures: Array(repeating: 0, count: Self.ruleNames.count),
                setsRootOnlyKeys: false
            )
        }
        let resolved = ResolvedConfigurationEngine()
            .resolve(at: Self.directories[Self.layerCount - 1], in: makeTree(from: specs))

        #expect(resolved.layerChain.count == Self.layerCount)
        #expect(resolved.disabledRules.isEmpty)
        #expect(resolved.optInRules.isEmpty)
        #expect(resolved.ruleConfigurations.isEmpty)
        #expect(resolved.excluded == nil)
    }

    // MARK: - The self-contradiction tie-break

    @Test("one layer listing a rule in both keys resolves to disabled")
    func sameLayerContradictionResolvesToDisabled() {
        // Matches SwiftLint 0.65.0, verified by running it: a config naming
        // `force_unwrapping` in both `disabled_rules` and `opt_in_rules` leaves
        // the rule silent on code that violates it, while `opt_in_rules` alone
        // reports it. A default rule (`todo`) behaves identically, and neither
        // case emits a warning — the contradiction is resolved, not rejected.
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.disabledRules = ["todo"]
        config.optInRules = ["todo"]

        let tree = ConfigTree(
            workspaceRoot: Self.root,
            configs: [makeDiscovered(directory: Self.root, depth: 0, config: config)]
        )
        let resolved = ResolvedConfigurationEngine().resolve(at: Self.root, in: tree)

        #expect(resolved.disabledRules.map(\.identifier) == ["todo"])
        #expect(resolved.optInRules.isEmpty)
    }

    @Test("a self-contradicting layer still loses to a deeper layer that opts in")
    func deeperOptInBeatsAShallowerContradiction() {
        // The tie-break is *within* a layer only — it must not make the disabled
        // side sticky across layers.
        var rootConfig = YAMLConfigurationEngine.YAMLConfig()
        rootConfig.disabledRules = ["todo"]
        rootConfig.optInRules = ["todo"]
        var childConfig = YAMLConfigurationEngine.YAMLConfig()
        childConfig.optInRules = ["todo"]

        let child = Self.directories[1]
        let tree = ConfigTree(
            workspaceRoot: Self.root,
            configs: [
                makeDiscovered(directory: Self.root, depth: 0, config: rootConfig),
                makeDiscovered(directory: child, depth: 1, config: childConfig)
            ]
        )
        let resolved = ResolvedConfigurationEngine().resolve(at: child, in: tree)

        #expect(resolved.disabledRules.isEmpty)
        #expect(resolved.optInRules.map(\.identifier) == ["todo"])
    }
}
