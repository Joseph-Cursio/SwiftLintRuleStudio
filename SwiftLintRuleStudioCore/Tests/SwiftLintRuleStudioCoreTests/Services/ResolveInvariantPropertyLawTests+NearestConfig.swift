//
//  ResolveInvariantPropertyLawTests+NearestConfig.swift
//  SwiftLintRuleStudioCoreTests
//
//  Which of the generated layers apply to the folder resolved. SwiftLint merges the root config
//  with the nearest nested config at or above a folder, and with no other
//  (`configuration(forDirectory:)`), so at /ws/a/b the layer at /ws/a decides nothing.
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

extension ResolveInvariantPropertyLawTests {
    /// The layers SwiftLint applies at `directories[target]`, root first: the
    /// root, then the target's own layer, which is the nearest nested config.
    nonisolated static func appliedLayers(at target: Int) -> [Int] {
        target == 0 ? [0] : [0, target]
    }

    /// Which of ``directories`` to resolve.
    nonisolated static func targetGenerator() -> Generator<Int, some SendableSequenceType> {
        Gen<Int>.int(in: 0 ... layerCount - 1)
    }

    @Test("a layer between the root and the nearest nested config contributes nothing")
    func skippedLayerContributesNothing() async {
        await propertyCheck(input: Self.layerSpecsGenerator()) { specs in
            let deepest = Self.directories[Self.layerCount - 1]
            let resolved = ResolvedConfigurationEngine().resolve(at: deepest, in: makeTree(from: specs))
            let withoutMiddle = ResolvedConfigurationEngine()
                .resolve(at: deepest, in: makeTree(from: specs, omitting: 1))

            // The middle layer is reported as passed over, not merged…
            #expect(resolved.layerChain.map(\.depth) == [0, Self.layerCount - 1])
            #expect(resolved.skippedLayers.map(\.depth) == [1])
            // …and every decision is what it would be were its folder to hold no config.
            #expect(Self.decisions(of: resolved) == Self.decisions(of: withoutMiddle))
        }
    }

    /// Everything a resolution decides, each with the depth of the layer that
    /// decided it — all of it but the chain itself.
    private static func decisions(of resolved: ResolvedConfiguration) -> [String] {
        let memberships = [
            ("disabled", resolved.disabledRules),
            ("opt-in", resolved.optInRules),
            ("analyzer", resolved.analyzerRules)
        ].flatMap { list, decisions in
            decisions.map { "\(list) \($0.identifier) by \($0.setBy.depth)" }
        }
        let configurations = resolved.ruleConfigurations.map { entry in
            let setting = "\(entry.identifier) \(entry.configuration.severity as Any) by \(entry.setBy.depth)"
            let previous = entry.previousSetBy.map { layer in
                "over \(entry.previousConfiguration?.severity as Any) by \(layer.depth)"
            }
            return "\(setting) \(previous ?? "over nothing")"
        }
        // Described whole: each names its layers, and the two trees share them.
        return memberships + configurations + [
            "only_rules \(String(describing: resolved.onlyRules))",
            "excluded \(String(describing: resolved.excluded))",
            "included \(String(describing: resolved.included))",
            "reporter \(String(describing: resolved.reporter))"
        ]
    }
}
