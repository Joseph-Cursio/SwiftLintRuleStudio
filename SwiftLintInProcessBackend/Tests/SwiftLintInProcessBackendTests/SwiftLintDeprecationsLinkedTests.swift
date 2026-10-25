import Foundation
import SwiftLintRuleStudioCore
import Testing

/// Core's deprecation tables, checked against the SwiftLint this package links.
///
/// The compatibility report's "Fix" and the migration assistant rewrite each renamed id in a
/// config. The tables once listed live rules as renamed (`generic_type_name` →
/// `identifier_name`, `multiple_closures_with_trailing_closure` → `trailing_closure`), so a
/// valid config was rewritten to run different rules, and the Core laws, which read the
/// tables, all held. SwiftLint's own record of a rename is a rule's `deprecatedAliases`.
@MainActor
@Suite
struct SwiftLintDeprecationsLinkedTests {

    private let identifiers = LinkedSwiftLintRules.identifiers
    private let aliases = LinkedSwiftLintRules.deprecatedAliases
    private let version = LinkedSwiftLintRules.version

    /// Whether the linked SwiftLint is at or past `threshold`.
    private func linkedVersionHas(_ threshold: String) -> Bool {
        !SwiftLintDeprecations.isVersion(version, lessThan: threshold)
    }

    // MARK: - Renames

    @Test("every rename target is a rule the linked SwiftLint has")
    func renameTargetsAreRules() {
        for (oldId, newId) in SwiftLintDeprecations.renamedRules {
            #expect(identifiers.contains(newId), "\(oldId) is renamed to \(newId), which is not a rule")
        }
    }

    @Test("no renamed identifier is still a rule of its own")
    func renamedIdsAreNotRules() {
        for oldId in SwiftLintDeprecations.renamedRules.keys {
            #expect(!identifiers.contains(oldId), "\(oldId) is listed as renamed but is a live rule")
        }
    }

    @Test("a rename SwiftLint still resolves names the rule that declares the alias")
    func renamesMatchTheAliases() {
        for (oldId, newId) in SwiftLintDeprecations.renamedRules {
            guard let declaringRule = aliases[oldId] else { continue }
            #expect(newId == declaringRule, "\(oldId) is an alias of \(declaringRule), not \(newId)")
        }
    }

    @Test("every deprecated alias in the linked SwiftLint is in the rename table")
    func everyAliasIsARename() {
        #expect(aliases.isEmpty == false)
        for (alias, ruleId) in aliases {
            #expect(SwiftLintDeprecations.renamedRules[alias] == ruleId, "\(alias) → \(ruleId) is missing")
        }
    }

    /// The checker and the migration hide a rename until the installed version has it, so a
    /// rename dated after the linked version would never be reported.
    @Test("every alias is renamed by the linked version")
    func aliasesAreDatedByTheLinkedVersion() {
        for alias in aliases.keys {
            let renamedIn = SwiftLintDeprecations.deprecatedRules[alias]?.deprecatedInVersion
            #expect(renamedIn.map(linkedVersionHas) == true, "\(alias) is renamed in \(renamedIn ?? "no version")")
        }
    }

    // MARK: - Deprecations and removals

    /// A deprecation with a replacement is a rename. One without names a rule on its way out,
    /// and every such rule in the tables is gone from the linked SwiftLint. When SwiftLint next
    /// deprecates a live rule, this fails until the tables record when it goes.
    @Test("every deprecation is an alias, or a rule removed by the linked version")
    func deprecationsAreKnown() {
        for (ruleId, entry) in SwiftLintDeprecations.deprecatedRules {
            if let replacement = entry.replacement {
                #expect(aliases[ruleId] == replacement, "\(ruleId) is not an alias of \(replacement)")
                continue
            }
            let removal = SwiftLintDeprecations.removedRules[ruleId]
            let removed = removal.map { linkedVersionHas($0.removedInVersion) } ?? false
            #expect(removed, "\(ruleId) is deprecated with no replacement but not removed")
        }
    }

    @Test("a removed rule is neither a rule nor an alias, and its replacement is a rule")
    func removedRulesAreGone() {
        for (ruleId, entry) in SwiftLintDeprecations.removedRules where linkedVersionHas(entry.removedInVersion) {
            #expect(!identifiers.contains(ruleId), "\(ruleId) is listed as removed but is a live rule")
            #expect(aliases[ruleId] == nil, "\(ruleId) is listed as removed but resolves as an alias")
            if let replacement = entry.replacement {
                #expect(identifiers.contains(replacement), "\(ruleId)'s replacement \(replacement) is not a rule")
            }
        }
    }

    // MARK: - Additions

    @Test("every added rule is a rule the linked SwiftLint has, or one it has removed")
    func addedRulesExist() {
        for (addedIn, ruleIds) in SwiftLintDeprecations.versionRuleAdditions where linkedVersionHas(addedIn) {
            for ruleId in ruleIds {
                let removal = SwiftLintDeprecations.removedRules[ruleId]
                let removed = removal.map { linkedVersionHas($0.removedInVersion) } ?? false
                #expect(identifiers.contains(ruleId) || removed, "\(ruleId), added in \(addedIn), is not a rule")
            }
        }
    }
}
