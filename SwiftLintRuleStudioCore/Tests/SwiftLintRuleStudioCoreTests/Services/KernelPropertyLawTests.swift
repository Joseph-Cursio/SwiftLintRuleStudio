//
//  KernelPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property-based laws (swift-property-based) for pure kernels the `swift-infer`
//  discover pass surfaced but could only characterize with the generic
//  determinism fallback: it has no *signal* that `deindent` is idempotent, that
//  `levenshtein` is a metric, or that `isVersion` is an ordering. Those laws are
//  human-stated here — the half of the loop the tool can't do — and pinned with
//  real generators + shrinking. Generators use deliberately tiny alphabets so
//  structure collides (the counterexamples live in the collisions).
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
@Suite("Kernel property laws")
struct KernelPropertyLawTests {

    // MARK: - Generators

    /// Lines with 0–6 leading spaces over a three-symbol alphabet, so a common
    /// indentation actually occurs (a wide alphabet rarely shares a prefix).
    static func linesGenerator() -> Generator<[String], some SendableSequenceType> {
        let token = Gen<Character>.character(in: "a"..."c").string(of: 0...4)
        let line = zip(Gen<Int>.int(in: 0...6), token).map { indent, text in
            String(repeating: " ", count: indent) + text
        }
        return line.array(of: 0...6)
    }

    /// Exclusion lists over an alphabet that overlaps the canonical defaults, so
    /// the dedup path is exercised. Returned non-optional; a `[String]` promotes to
    /// `[String]?` at the call site.
    static func exclusionListGenerator() -> Generator<[String], some SendableSequenceType> {
        let names = [".build", "Pods", "Build", ".git", "Custom", "MyDir"]
        let entry = Gen<Int>.int(in: 0 ... (names.count - 1)).map { names[$0] }
        return entry.array(of: 0...6)
    }

    /// Short strings over a three-symbol alphabet, so edit-distance collisions
    /// are common.
    static func smallStringGenerator() -> Generator<String, some SendableSequenceType> {
        Gen<Character>.character(in: "a"..."c").string(of: 0...6)
    }

    /// Dotted version strings with small numeric components, so orderings tie and
    /// cross often.
    static func versionGenerator() -> Generator<String, some SendableSequenceType> {
        let component = Gen<Int>.int(in: 0...3).map { String($0) }
        return component
            .array(of: 1...3)
            .map { $0.joined(separator: ".") }
    }

    // MARK: - deindent — idempotence

    @Test("deindent is idempotent")
    func deindentIsIdempotent() async {
        await propertyCheck(input: Self.linesGenerator()) { lines in
            let once = RuleParameterParser.deindent(lines)
            #expect(RuleParameterParser.deindent(once) == once)
        }
    }

    // MARK: - mergedWith — idempotence + completeness + prefix

    @Test("mergedWith is idempotent, complete, and preserves existing as a prefix")
    func mergedWithLaws() async {
        await propertyCheck(input: Self.exclusionListGenerator()) { list in
            let once = DefaultExclusions.mergedWith(existing: list)
            #expect(DefaultExclusions.mergedWith(existing: once) == once)
            #expect(Set(DefaultExclusions.directories).isSubset(of: Set(once)))
            if !list.isEmpty {
                #expect(Array(once.prefix(list.count)) == list)
            }
        }
    }

    @Test("mergedWith(nil) and mergedWith([]) return exactly the defaults")
    func mergedWithEmptyReturnsDefaults() {
        #expect(DefaultExclusions.mergedWith(existing: nil) == DefaultExclusions.directories)
        #expect(DefaultExclusions.mergedWith(existing: []) == DefaultExclusions.directories)
    }

    // MARK: - mergedWith — associativity of the union underneath it

    /// The binary operation `mergedWith(existing:)` is a section of: an
    /// order-preserving, left-biased union. `lhs` survives verbatim; `rhs`
    /// contributes only what `lhs` does not already contain.
    ///
    /// Stated here rather than in production because the app never needs the
    /// binary form — but the *laws* are about the binary operation, and a unary
    /// function has no associativity to test. This is the reference definition
    /// the law checks `mergedWith` against.
    nonisolated private static func merge(_ lhs: [String], _ rhs: [String]) -> [String] {
        let seen = Set(lhs)
        return lhs + rhs.filter { !seen.contains($0) }
    }

    @Test("the union under mergedWith is associative and idempotent")
    func mergeIsAssociative() async {
        await propertyCheck(
            input: Self.exclusionListGenerator(),
            Self.exclusionListGenerator(),
            Self.exclusionListGenerator()
        ) { first, second, third in
            // Associativity — the law §8 asks for. Both groupings emit
            // `first`, then second-minus-first, then third-minus-either.
            #expect(
                Self.merge(Self.merge(first, second), third)
                    == Self.merge(first, Self.merge(second, third))
            )

            // Idempotence — merging a list with itself adds nothing.
            #expect(Self.merge(first, first) == first)

            // Left identity. (There is no right identity that is also a left
            // one: `merge([], x)` is `x`, but `merge(x, [])` is `x` too, so
            // `[]` is two-sided — assert both rather than assume.)
            #expect(Self.merge([], first) == first)
            #expect(Self.merge(first, []) == first)
        }
    }

    @Test("mergedWith is exactly the union against the defaults, guard included")
    func mergedWithIsASectionOfMerge() async {
        await propertyCheck(input: Self.exclusionListGenerator()) { list in
            // The `guard existing.isEmpty` branch is a fast path, not a different
            // answer: the general formula already yields the defaults for an
            // empty input. A future edit that makes the two disagree fails here.
            #expect(
                DefaultExclusions.mergedWith(existing: list)
                    == Self.merge(list, DefaultExclusions.directories)
            )
        }
        #expect(DefaultExclusions.mergedWith(existing: nil) == Self.merge([], DefaultExclusions.directories))
    }

    @Test("the union commutes as a set, but not as a list")
    func mergeCommutesOnlyAsASet() async {
        await propertyCheck(input: Self.exclusionListGenerator(), Self.exclusionListGenerator()) { first, second in
            let forward = Self.merge(first, second)
            let backward = Self.merge(second, first)

            // Commutative on membership...
            #expect(Set(forward) == Set(first).union(Set(second)))
            #expect(Set(forward) == Set(backward))

            // ...but the left operand keeps its position and its order, which is
            // what makes the operation order-preserving rather than a set union.
            #expect(Array(forward.prefix(first.count)) == first)
            #expect(Array(backward.prefix(second.count)) == second)
        }
    }

    @Test("each element keeps the multiplicity of whichever side supplied it")
    func mergePreservesMultiplicityFromItsSource() async {
        await propertyCheck(input: Self.exclusionListGenerator(), Self.exclusionListGenerator()) { first, second in
            let merged = Self.merge(first, second)

            // NOT "the result is deduplicated" — `mergedWith`'s docstring claims
            // that and it is false. Repeats survive from *whichever side supplied
            // the element*: the left operand is copied verbatim, and an element the
            // left lacks arrives with all of the right's copies. Deduplicating
            // would contradict the shipped prefix law, so the true statement is
            // about multiplicity, not distinctness.
            let inFirst = Set(first)
            for value in Set(merged) {
                let expected = inFirst.contains(value)
                    ? first.filter { $0 == value }.count
                    : second.filter { $0 == value }.count
                #expect(merged.filter { $0 == value }.count == expected)
            }

            // The contributed tail is disjoint from the left operand — that part
            // of "deduplicated" does hold, and it is what dedupes across the seam.
            let tail = Array(merged.dropFirst(first.count))
            #expect(Set(tail).isDisjoint(with: inFirst))
        }
    }

    // MARK: - levenshteinDistance — metric laws

    @Test("levenshtein distance is symmetric, non-negative, and zero iff equal")
    func levenshteinMetricBasics() async {
        let validator = ConfigurationValidator()
        await propertyCheck(input: Self.smallStringGenerator(), Self.smallStringGenerator()) { lhs, rhs in
            let forward = validator.levenshteinDistance(lhs, rhs)
            let backward = validator.levenshteinDistance(rhs, lhs)
            #expect(forward == backward)
            #expect(forward >= 0)
            #expect((forward == 0) == (lhs == rhs))
        }
    }

    @Test("levenshtein distance satisfies the triangle inequality")
    func levenshteinTriangleInequality() async {
        let validator = ConfigurationValidator()
        await propertyCheck(
            input: Self.smallStringGenerator(), Self.smallStringGenerator(), Self.smallStringGenerator()
        ) { lhs, mid, rhs in
            let direct = validator.levenshteinDistance(lhs, rhs)
            let viaMid = validator.levenshteinDistance(lhs, mid) + validator.levenshteinDistance(mid, rhs)
            #expect(direct <= viaMid)
        }
    }

    // MARK: - isVersion — strict weak ordering

    @Test("isVersion is irreflexive and asymmetric")
    func isVersionIrreflexiveAsymmetric() async {
        await propertyCheck(input: Self.versionGenerator(), Self.versionGenerator()) { lhs, rhs in
            #expect(!SwiftLintDeprecations.isVersion(lhs, lessThan: lhs))
            if SwiftLintDeprecations.isVersion(lhs, lessThan: rhs) {
                #expect(!SwiftLintDeprecations.isVersion(rhs, lessThan: lhs))
            }
        }
    }

    @Test("isVersion is transitive")
    func isVersionTransitive() async {
        await propertyCheck(
            input: Self.versionGenerator(), Self.versionGenerator(), Self.versionGenerator()
        ) { lhs, mid, rhs in
            if SwiftLintDeprecations.isVersion(lhs, lessThan: mid),
               SwiftLintDeprecations.isVersion(mid, lessThan: rhs) {
                #expect(SwiftLintDeprecations.isVersion(lhs, lessThan: rhs))
            }
        }
    }
}
