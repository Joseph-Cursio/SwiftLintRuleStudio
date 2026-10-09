import Foundation
@testable import SwiftLintInProcessBackend
import SwiftLintRuleStudioCore
import Testing

// Core's `SwiftLintDeprecations` is hand-written and can't see SwiftLint; this package
// links the real thing, so it checks the table against the rules SwiftLint registers.
// Migration and Version Check offer every rename in the table as a one-click fix, and the
// table once renamed two live rules: `multiple_closures_with_trailing_closure` (on by
// default) to `trailing_closure` (opt-in), and `generic_type_name` to `identifier_name`.
// Core is built with `.defaultIsolation(MainActor.self)`, so the suite opts in.
@Suite("Deprecation data against the linked SwiftLint")
@MainActor
struct DeprecationDataTests {

    /// The primary identifier of every built-in rule. Deprecated aliases are left out:
    /// a rule that survives only as an alias has been renamed (see
    /// `deprecatedAliasesAreRenamesToTheirRule`).
    private static let liveRules = Set(
        // A key path to a static member through `any Rule.Type` crashes the Swift 6.4 compiler.
        // swiftlint:disable:next prefer_key_path
        SwiftLintInProcessActor.sortedBuiltInRules().map { $0.description.identifier }
    )

    @Test
    func renamesStartFromRulesThatNoLongerExist() {
        let live = SwiftLintDeprecations.renamedRules.keys.filter(Self.liveRules.contains)
        #expect(live.isEmpty, "Renamed rules that still exist: \(live.sorted())")
    }

    @Test
    func renamesEndAtRulesThatExist() {
        let missing = SwiftLintDeprecations.renamedRules.values.filter { !Self.liveRules.contains($0) }
        #expect(missing.isEmpty, "Rename targets that don't exist: \(Set(missing).sorted())")
    }

    @Test
    func deprecatedRulesAreGoneAndPointAtRulesThatExist() {
        let live = SwiftLintDeprecations.deprecatedRules.keys.filter(Self.liveRules.contains)
        #expect(live.isEmpty, "Deprecated rules that are still current: \(live.sorted())")
        let missing = SwiftLintDeprecations.deprecatedRules.values
            .compactMap(\.replacement)
            .filter { !Self.liveRules.contains($0) }
        #expect(missing.isEmpty, "Replacements that don't exist: \(Set(missing).sorted())")
    }

    @Test
    func removedRulesAreGoneAndPointAtRulesThatExist() {
        let live = SwiftLintDeprecations.removedRules.keys.filter(Self.liveRules.contains)
        #expect(live.isEmpty, "Removed rules that still exist: \(live.sorted())")
        let missing = SwiftLintDeprecations.removedRules.values
            .compactMap(\.replacement)
            .filter { !Self.liveRules.contains($0) }
        #expect(missing.isEmpty, "Replacements that don't exist: \(Set(missing).sorted())")
    }

    /// SwiftLint still accepts a deprecated alias and lints it as the rule that owns it, so
    /// the alias is a rename to that rule, never a removal.
    @Test
    func deprecatedAliasesAreRenamesToTheirRule() {
        for ruleType in SwiftLintInProcessActor.sortedBuiltInRules() {
            let rule = ruleType.description
            for alias in rule.deprecatedAliases {
                #expect(SwiftLintDeprecations.renamedRules[alias] == rule.identifier, "Alias '\(alias)'")
                #expect(SwiftLintDeprecations.removedRules[alias] == nil, "Alias '\(alias)' still resolves")
            }
        }
    }

    /// Version Check lists these as rules the config could enable.
    @Test
    func addedRulesExistOrWereRemoved() {
        let unknown = SwiftLintDeprecations.versionRuleAdditions.values.joined().filter {
            !Self.liveRules.contains($0) && SwiftLintDeprecations.removedRules[$0] == nil
        }
        #expect(unknown.isEmpty, "Added rules SwiftLint doesn't have: \(Set(unknown).sorted())")
    }
}
