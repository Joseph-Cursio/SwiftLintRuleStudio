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
        SwiftLintInProcessActor.sortedRules().map { $0.description.identifier }
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

    /// The linked SwiftLint's version, e.g. "0.65.0".
    private static let linkedVersion = (try? SwiftLintInProcessActor().getVersion()) ?? ""

    /// Whether the linked SwiftLint is at or past `version`.
    private static func linkedVersionHas(_ version: String) -> Bool {
        !SwiftLintDeprecations.isVersion(linkedVersion, lessThan: version)
    }

    /// Each deprecated alias, mapped to the rule that declares it.
    private static let deprecatedAliases: [String: String] = {
        var aliases: [String: String] = [:]
        for ruleType in SwiftLintInProcessActor.sortedRules() {
            let rule = ruleType.description
            for alias in rule.deprecatedAliases { aliases[alias] = rule.identifier }
        }
        return aliases
    }()

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
        for ruleType in SwiftLintInProcessActor.sortedRules() {
            let rule = ruleType.description
            for alias in rule.deprecatedAliases {
                #expect(SwiftLintDeprecations.renamedRules[alias] == rule.identifier, "Alias '\(alias)'")
                #expect(SwiftLintDeprecations.removedRules[alias] == nil, "Alias '\(alias)' still resolves")
            }
        }
    }

    /// The config summary reads a rule under its alias as the same rule, so the table must be
    /// exactly SwiftLint's aliases: no more, no fewer.
    @Test
    func ruleAliasesAreSwiftLintsDeprecatedAliases() {
        var aliases: [String: String] = [:]
        for ruleType in SwiftLintInProcessActor.sortedRules() {
            let rule = ruleType.description
            for alias in rule.deprecatedAliases { aliases[alias] = rule.identifier }
        }
        #expect(SwiftLintDeprecations.ruleAliases == aliases)
    }

    /// A deprecation with a replacement is a rename: of an alias SwiftLint still reads, to the
    /// rule that declares it, or else one `renamedRules` records. One without is a rule on its
    /// way out, and every such rule in the table is gone from the linked SwiftLint; when
    /// SwiftLint next deprecates a live rule, this fails until the table records its removal.
    @Test
    func deprecationsAreRenamesOrRemovals() {
        for (ruleId, entry) in SwiftLintDeprecations.deprecatedRules {
            if let replacement = entry.replacement {
                let renamedTo = Self.deprecatedAliases[ruleId] ?? SwiftLintDeprecations.renamedRules[ruleId]
                #expect(renamedTo == replacement, "'\(ruleId)' is deprecated for '\(replacement)'")
                continue
            }
            let removedIn = SwiftLintDeprecations.removedRules[ruleId]?.removedInVersion
            #expect(removedIn.map(Self.linkedVersionHas) == true, "'\(ruleId)' is deprecated but not removed")
        }
    }

    /// Version Check and the Migration Assistant hide a rename until the installed version has
    /// it, so a rename dated after the linked version would never be reported.
    @Test
    func aliasesAreRenamedByTheLinkedVersion() {
        for alias in Self.deprecatedAliases.keys {
            let renamedIn = SwiftLintDeprecations.deprecatedRules[alias]?.deprecatedInVersion
            let dated = renamedIn.map(Self.linkedVersionHas) == true
            #expect(dated, "'\(alias)' is renamed in \(renamedIn ?? "no version")")
        }
    }

    /// Version Check lists these as rules the config could enable. A rule added after the
    /// linked version (`legacy_swiftui_aspect_ratio`, 0.65.1) can't be checked against it.
    @Test
    func addedRulesExistOrWereRemoved() {
        #expect(!Self.linkedVersion.isEmpty)
        let unknown = SwiftLintDeprecations.versionRuleAdditions
            .filter { Self.linkedVersionHas($0.key) }
            .values.joined()
            .filter { !Self.liveRules.contains($0) && SwiftLintDeprecations.removedRules[$0] == nil }
        #expect(unknown.isEmpty, "Added rules SwiftLint doesn't have: \(Set(unknown).sorted())")
    }
}
