//
//  LayerChainPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for `ResolvedConfigurationEngine.layerChain` — a path-prefix
//  *selection* the toolchain could only give the non-refutable determinism law
//  (no template names a selection/ancestry shape). Hand-stating the reference
//  definition is the point: a correct layerChain returns exactly the configs
//  whose directory is an ancestor of the target, drawn from the tree, ordered by
//  depth. Generators draw directories from a three-name alphabet so ancestry
//  actually occurs — the counterexamples live where prefixes nearly coincide.
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
            id: UUID(),
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
            .map { ConfigTree(workspaceRoot: root, configs: $0) }
    }

    private static func targetGenerator() -> Generator<URL, some SendableSequenceType> {
        directoryGenerator().map { $0.0 }
    }

    @Test("layerChain selects tree ancestors of the target, ordered by depth")
    func layerChainLaws() async {
        await propertyCheck(input: Self.treeGenerator(), Self.targetGenerator()) { tree, target in
            let chain = ResolvedConfigurationEngine.layerChain(for: target, in: tree)
            let targetComponents = target.standardizedFileURL.pathComponents

            // Ancestry — every selected config governs a directory that is a prefix
            // (ancestor) of the target directory.
            for config in chain {
                let directoryComponents = config.directoryPath.standardizedFileURL.pathComponents
                #expect(directoryComponents.count <= targetComponents.count)
                #expect(Array(targetComponents.prefix(directoryComponents.count)) == directoryComponents)
            }

            // From the tree — the chain invents no config.
            let treeDirectories = Set(tree.configs.map { $0.directoryPath.standardizedFileURL.path })
            #expect(chain.allSatisfy { treeDirectories.contains($0.directoryPath.standardizedFileURL.path) })

            // Ordered by depth ascending — the root layer first.
            #expect(chain.map(\.depth) == chain.map(\.depth).sorted())
        }
    }
}
