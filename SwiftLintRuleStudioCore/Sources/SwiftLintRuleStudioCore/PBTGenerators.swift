import Foundation
import PropertyBased

// PBT adoption — `gen()` escape hatches for swift-infer verify.
//
// swift-infer's derivation engine can compose generators for value types whose
// members bottom out in recognized raw/known types, but it dead-ends on two
// leaves in this module:
//   - `AnyCodable` wraps `Any` (no structure to derive a generator from), and
//   - `URL` is an external Foundation type outside the scanned universe.
//
// Every value-type carrier here (`RuleParameter`, `RuleParameterValues`, and any
// `[Rule]`-shaped carrier) funnels through one of those two, so verify reports
// `unsupported-carrier` for all of them. The `static func gen()` convention is
// swift-infer's explicit opt-in: when a carrier (or a nested type a carrier
// derives through) declares one, the engine references it as `T.gen()` instead
// of trying to synthesize a generator. Providing these two unblocks the whole
// value-type surface that funnels through them.
//
// Both are `nonisolated` so the generated verify stub (which runs in a
// nonisolated context) can call them under this package's
// `defaultIsolation(MainActor.self)` setting. Both draw from the seeded `Gen`
// combinators — never `.random` — so verify runs stay reproducible from a seed.

extension AnyCodable {
    /// Generates `AnyCodable` values wrapping a bounded `Int` — the JSON
    /// primitive `RuleParameter.intValue(for:)` and friends actually read.
    nonisolated static func gen() -> Generator<AnyCodable, some SendableSequenceType> {
        Gen<Int>.int(in: -1_000 ... 1_000).map { AnyCodable($0) }
    }
}

extension URL {
    /// Generates well-formed `https://` URLs with an alphanumeric path.
    nonisolated static func gen() -> Generator<URL, some SendableSequenceType> {
        Gen<Character>.letterOrNumber.string(of: 1 ... 8).map { path in
            URL(string: "https://example.com/\(path)")!
        }
    }
}
