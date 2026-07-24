//
//  Node+Generator.swift
//  SwiftLintRuleStudioCoreTests
//
//  A generator for Yams' `Node`, an external type the `swift-infer` strategist
//  cannot derive. `YAMLConfig.passthroughNodes` is `[String: Node]`, so `Node`
//  is the member the strategist names when it declines to compose the carrier.
//
//  Registered for the toolchain in `.swiftinfer/vocabulary.json` as
//  `{ "Node": { "expression": "Node.gen()", "imports": ["Yams"] } }`; keep the
//  name `gen()` in step with that expression, which `discover` splices verbatim.
//
//  MEASURED, 2026-07-24: registering this changes nothing today. `discover` on
//  this package reports the same 14 suggestions and the same 7 `.todo`
//  generators with the registration present, absent, or passed explicitly via
//  `--vocabulary`, and `generateDiff` stays `Generator: .todo`. `swift-infer
//  scaffold` shows why the registration cannot bite: of 21 emitted stubs,
//  neither `YAMLConfig` nor `ConfigDiff` is among them — both appear only as
//  unresolved `<#Generator<YAMLConfigurationEngine.YAMLConfig>#>` placeholders
//  inside *other* types' generators. The carrier is never derived at all, so a
//  missing member generator was never the binding constraint. Kept because it
//  is correct and costs nothing; it starts paying if that changes upstream.
//
//  Deliberately narrow: scalars over a three-symbol alphabet, or a one-level
//  sequence / mapping built from those scalars. Passthrough nodes are values the
//  engine carries without interpreting, so a law over them wants *collisions* —
//  repeated keys and equal-looking scalars — not variety.
//

import PropertyBased
import Yams

extension Node {

    /// A small `Node`: a scalar, a one-level sequence, or a one-level mapping,
    /// all drawn from a three-symbol alphabet.
    ///
    /// The alphabet is intentionally tiny so distinct nodes compare equal often
    /// — the collisions are where a passthrough that confuses identity with
    /// equality gives itself away.
    static func gen() -> Generator<Node, some SendableSequenceType> {
        let symbols = Gen<String?>.element(of: ["alpha", "beta", "gamma"]).map { $0 ?? "alpha" }

        return zip(Gen<Int>.int(in: 0...2), symbols.array(of: 0...2)).map { shape, values in
            switch shape {
            case 0:
                return Node(values.first ?? "alpha")
            case 1:
                return Node(values.map { Node($0) })
            default:
                return Node(values.map { (Node($0), Node($0)) })
            }
        }
    }
}
