//
//  LayerChainPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for `ResolvedConfigurationEngine.layerChain` — a path-prefix
//  *selection* the toolchain could only give the non-refutable determinism law
//  (no template names a selection/ancestry shape). Hand-stating the reference
//  definition is the point. SwiftLint applies to a folder the root configuration
//  — the root config with the configs it pulls in with `parent_config` and
//  `child_config`, in their order — and the first nested `.swiftlint.yml` outside
//  that graph it meets walking up from there, and no other
//  (`configuration(forDirectory:)`). So a correct layerChain returns, drawn from
//  the tree, the root graph, then the deepest of the target's other ancestor
//  configs — passing over the ones between. Generators draw directories from a
//  three-name alphabet so ancestry actually occurs — the counterexamples live
//  where prefixes nearly coincide — keep one config per directory, as a workspace
//  does (a config is the file at its path), and pull some nested configs into the
//  root's graph when there is a root config to pull them in.
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

@Suite("layerChain property laws")
struct LayerChainPropertyLawTests {

    nonisolated private static let root = URL(fileURLWithPath: "/ws")

    nonisolated private static func makeConfig(
        directory: URL,
        depth: Int,
        rootGraphPosition: Int?
    ) -> DiscoveredConfig {
        DiscoveredConfig(
            configPath: directory.appendingPathComponent(".swiftlint.yml"),
            directoryPath: directory,
            relativePath: ".swiftlint.yml",
            depth: depth,
            isRoot: depth == 0,
            parentID: nil,
            config: nil,
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
            ),
            rootGraphPosition: rootGraphPosition
        )
    }

    /// A directory under `/ws` built from 0–3 components over a three-name
    /// alphabet, paired with its depth. Small alphabet ⇒ shared prefixes.
    private static func directoryGenerator() -> Generator<(URL, Int), some SendableSequenceType> {
        let component = Gen<Int>.int(in: 0...2).map { ["a", "b", "c"][$0] }
        return component.array(of: 0...3).map { components in
            let directory = components.isEmpty
                ? root
                : root.appendingPathComponent(components.joined(separator: "/"))
            return (directory, components.count)
        }
    }

    /// Up to five configs in distinct directories. Each nested one is drawn with a
    /// pull — 1 the root's `child_config` chain, 2 its `parent_config` chain, else
    /// neither — that counts only when the tree has a root config to pull it in.
    private static func treeGenerator() -> Generator<ConfigTree, some SendableSequenceType> {
        zip(directoryGenerator(), Gen<Int>.int(in: 0...3))
            .array(of: 0...5)
            .map { drawn in
                var directories: Set<String> = []
                let unique = drawn.filter { directories.insert($0.0.0.standardizedFileURL.path).inserted }
                let hasRoot = unique.contains { $0.0.1 == 0 }
                var lastChild = 0
                var lastParent = 0
                let configs = unique.map { located, pull in
                    var position: Int?
                    if hasRoot, located.1 > 0, pull == 1 {
                        lastChild += 1
                        position = lastChild
                    } else if hasRoot, located.1 > 0, pull == 2 {
                        lastParent -= 1
                        position = lastParent
                    }
                    return makeConfig(directory: located.0, depth: located.1, rootGraphPosition: position)
                }
                return ConfigTree(workspaceRoot: root, configs: configs)
            }
    }

    nonisolated private static func isAncestor(_ config: DiscoveredConfig, of target: URL) -> Bool {
        let targetComponents = target.standardizedFileURL.pathComponents
        let directoryComponents = config.directoryPath.standardizedFileURL.pathComponents
        return directoryComponents.count <= targetComponents.count
            && Array(targetComponents.prefix(directoryComponents.count)) == directoryComponents
    }

    private static func targetGenerator() -> Generator<URL, some SendableSequenceType> {
        directoryGenerator().map(\.0)
    }

    @Test("layerChain is the root graph, then the target's nearest nested config outside it")
    func layerChainLaws() async {
        await propertyCheck(input: Self.treeGenerator(), Self.targetGenerator()) { tree, target in
            let chain = ResolvedConfigurationEngine.layerChain(for: target, in: tree)
            let ancestors = tree.configs.filter { Self.isAncestor($0, of: target) }
            let rootGraph = tree.configs.filter { $0.isRoot || $0.rootGraphPosition != nil }

            // From the tree — the chain invents no config.
            let treeDirectories = Set(tree.configs.map(\.directoryPath.standardizedFileURL.path))
            #expect(chain.allSatisfy { treeDirectories.contains($0.directoryPath.standardizedFileURL.path) })

            // The root graph applies wherever the target is — and every target here
            // is under the root — first, and in the order SwiftLint merges it: the
            // furthest parent first, the root at 0, the last child last.
            let graphPart = Array(chain.prefix(rootGraph.count))
            #expect(Set(graphPart.map(\.id)) == Set(rootGraph.map(\.id)))
            #expect(graphPart.map { $0.rootGraphPosition ?? 0 } == graphPart.map { $0.rootGraphPosition ?? 0 }.sorted())

            // Then one nested config at most, and the nearest outside the graph: an
            // ancestor of the target that no other such ancestor is deeper than, and
            // there is one whenever the target has such an ancestor at all.
            let nested = Array(chain.dropFirst(rootGraph.count))
            let candidates = ancestors.filter { !$0.isRoot && $0.rootGraphPosition == nil }
            #expect(nested.count <= 1)
            #expect(nested.isEmpty == candidates.isEmpty)
            if let nearest = nested.first {
                #expect(Self.isAncestor(nearest, of: target))
                #expect(candidates.allSatisfy { $0.depth <= nearest.depth })
            }
        }
    }

    @Test("the configs passed over are the target's other ancestor configs, all above the nearest one")
    func skippedLayersLaws() async {
        await propertyCheck(input: Self.treeGenerator(), Self.targetGenerator()) { tree, target in
            let resolved = ResolvedConfigurationEngine().resolve(at: target, in: tree)
            let ancestors = tree.configs.filter { Self.isAncestor($0, of: target) }
            let chainIDs = Set(resolved.layerChain.map(\.id))

            // Exactly the ancestors the chain leaves out — no sibling, no config
            // elsewhere in the tree, none the chain holds.
            #expect(Set(resolved.skippedLayers.map(\.id)) == Set(ancestors.map(\.id)).subtracting(chainIDs))
            #expect(resolved.skippedLayers.map(\.depth) == resolved.skippedLayers.map(\.depth).sorted())

            // Each is nested, outside the root graph, and above the nearest config.
            let rootGraphIDs = Set(tree.rootGraph.map(\.id))
            let nearestDepth = resolved.layerChain.last { !rootGraphIDs.contains($0.id) }?.depth
            for skipped in resolved.skippedLayers {
                #expect(!skipped.isRoot)
                #expect(!rootGraphIDs.contains(skipped.id))
                #expect(skipped.depth < (nearestDepth ?? 0))
            }
        }
    }
}
