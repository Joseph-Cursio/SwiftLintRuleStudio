//
//  RuleValueTypePropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property-based law checks (SwiftPropertyLaws) for the model value types the
//  config layer round-trips: `AnyCodable` and `RuleParameter`. These verify the
//  Hashable + Codable conformances behave correctly over generated inputs
//  (reflexivity, hash/equality consistency, encode→decode fidelity).
//
//  Deliberately in the TEST target: PropertyLawKit pulls swift-testing, which
//  can't link into the shipping app. Keeping it here is what an earlier attempt
//  to put generators in the Core library (404e6fd) got wrong — that broke the
//  app build.
//

import Foundation
import PropertyBased
import PropertyLawKit
import Testing
@testable import SwiftLintRuleStudioCore

@Suite("Rule value-type property laws")
struct RuleValueTypePropertyLawTests {

    // MARK: - Generators

    /// `AnyCodable` wrapping the JSON primitives it actually stores — a mix of
    /// `Int`, `String`, and `Bool` so the Codable round-trip exercises all three
    /// single-value encodings (and the decoder's Int-before-Bool ordering).
    static func anyCodableGenerator() -> Generator<AnyCodable, some SendableSequenceType> {
        Gen.frequency(
            (3.0, Gen<Int>.int(in: -1_000 ... 1_000).map { AnyCodable($0) }),
            (2.0, Gen<Character>.letterOrNumber.string(of: 0 ... 8).map { AnyCodable($0) }),
            (1.0, Gen<Int>.int(in: 0 ... 1).map { AnyCodable($0 == 0) })
        )
    }

    /// A `RuleParameter` with a generated name, one of the four parameter types,
    /// a generated `AnyCodable` default, and an optional description.
    static func ruleParameterGenerator() -> Generator<RuleParameter, some SendableSequenceType> {
        let names = Gen<Character>.letterOrNumber.string(of: 1 ... 10)
        let types = Gen<Int>.int(in: 0 ... 3).map { index in
            [ParameterType.integer, .string, .boolean, .array][index]
        }
        let descriptions = Gen<Character>.letterOrNumber.string(of: 0 ... 12).map { text in
            text.isEmpty ? String?.none : text
        }
        return zip(names, types, anyCodableGenerator(), descriptions).map { name, type, value, description in
            RuleParameter(name: name, type: type, defaultValue: value, description: description)
        }
    }

    // MARK: - AnyCodable

    @Test("AnyCodable satisfies the Hashable laws")
    func anyCodableHashable() async throws {
        let results = try await checkHashablePropertyLaws(using: Self.anyCodableGenerator())
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { !$0.isViolation })
    }

    @Test("AnyCodable satisfies the Codable round-trip laws")
    func anyCodableCodable() async throws {
        let results = try await checkCodablePropertyLaws(using: Self.anyCodableGenerator())
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { !$0.isViolation })
    }

    // MARK: - RuleParameter

    @Test("RuleParameter satisfies the Hashable laws")
    func ruleParameterHashable() async throws {
        let results = try await checkHashablePropertyLaws(using: Self.ruleParameterGenerator())
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { !$0.isViolation })
    }

    @Test("RuleParameter satisfies the Codable round-trip laws")
    func ruleParameterCodable() async throws {
        let results = try await checkCodablePropertyLaws(using: Self.ruleParameterGenerator())
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { !$0.isViolation })
    }
}
