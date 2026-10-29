//
//  LayerChainPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for `ResolvedConfigurationEngine.layerChain` — a path-prefix
//  *selection* the toolchain could only give the non-refutable determinism law
//  (no template names a selection/ancestry shape). Hand-stating the reference
//  definition is the point. SwiftLint applies to a folder the root config and the
//  first nested `.swiftlint.yml` it meets walking up from there, and no other
//  (`configuration(forDirectory:)`), so a correct layerChain returns, drawn from
//  the tree and ordered by depth, the root config and the deepest of the target's
//  other ancestor configs — passing over the ones between. Generators draw
//  directories from a three-name alphabet so ancestry actually occurs — the
//  counterexamples live where prefixes nearly coincide — and keep one config per
//  directory, as a workspace does: a config is the file at its path.
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

@Suite("layerChain property laws")
struct LayerChainPropertyLawTests {

    nonisolated private static let root = URL(fileURLWithPath: "/ws")

    nonisolated private static func makeConfig(directory: URL, depth: Int) -> DiscoveredConfig {
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
            )
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

    private static func treeGenerator() -> Generator<ConfigTree, some SendableSequenceType> {
        directoryGenerator()
            .map { makeConfig(directory: $0.0, depth: $0.1) }
            .array(of: 0...5)
            .map { configs in
                var directories: Set<String> = []
                return configs.filter { directories.insert($0.directoryPath.standardizedFileURL.path).inserted }
            }
            .map { ConfigTree(workspaceRoot: root, configs: $0) }
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

    @Test("layerChain is the root config and the target's nearest nested config, ordered by depth")
    func layerChainLaws() async {
        await propertyCheck(input: Self.treeGenerator(), Self.targetGenerator()) { tree, target in
            let chain = ResolvedConfigurationEngine.layerChain(for: target, in: tree)
            let ancestors = tree.configs.filter { Self.isAncestor($0, of: target) }

            // Ancestry — every selected config governs a directory that is a prefix
            // (ancestor) of the target directory.
            #expect(chain.allSatisfy { Self.isAncestor($0, of: target) })

            // From the tree — the chain invents no config.
            let treeDirectories = Set(tree.configs.map(\.directoryPath.standardizedFileURL.path))
            #expect(chain.allSatisfy { treeDirectories.contains($0.directoryPath.standardizedFileURL.path) })

            // Ordered by depth ascending — the root layer first.
            #expect(chain.map(\.depth) == chain.map(\.depth).sorted())

            // The root config applies wherever it is an ancestor — and every target
            // here is under the root.
            #expect(chain.filter(\.isRoot).count == ancestors.filter(\.isRoot).count)

            // One nested config at most, and the nearest: none of the target's
            // ancestor configs is deeper than it, and there is one whenever the
            // target has a nested ancestor config at all.
            let nested = chain.filter { !$0.isRoot }
            #expect(nested.count <= 1)
            #expect(nested.isEmpty == ancestors.allSatisfy(\.isRoot))
            if let nearest = nested.first {
                #expect(ancestors.allSatisfy { $0.depth <= nearest.depth })
            }
        }
    }
}
