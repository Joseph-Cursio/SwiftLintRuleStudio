//
//  YAMLConfigurationEngine.YAMLConfig+RuleRename.swift
//  SwiftLintRuleStudio
//
//  Renaming a rule identifier everywhere a configuration names it
//

import Foundation
import Yams

public extension YAMLConfigurationEngine.YAMLConfig {

    /// Every rule id the configuration names, as written, including rule keys whose value the
    /// engine does not model and keeps only as a passthrough node, such as the severity shorthand
    /// `redundant_self_in_closure: error`. `ruleIds` leaves those out, and `namedRuleIds` reads
    /// every alias as its current name; the compatibility check and the migration need the old
    /// names, or a renamed rule is never reported or renamed.
    var ruleIdsAsWritten: Set<String> {
        ruleIds.union(unmodeledRuleKeys)
    }

    /// Rule keys whose value the engine does not model, held only as passthrough nodes:
    /// every passthrough key that is not one of SwiftLint's own top-level options.
    internal var unmodeledRuleKeys: Set<String> {
        Set(passthroughNodes.keys.filter { !YAMLConfigurationEngine.reservedTopLevelKeys.contains($0) })
    }

    /// Renames rule `oldId` to `newId` in the rule configurations and in all four rule lists.
    ///
    /// A rule's configuration is either modeled in `rules` or, when the engine cannot model its
    /// value (`redundant_self_in_closure: error`), held as a passthrough node; both are renamed.
    /// When only the old id is configured, its configuration takes the new name in place, keeping
    /// its position in the file, its comment block and its scalar shorthand.
    ///
    /// When both are, SwiftLint rejects the file ("Multiple configurations found"), so the two
    /// merge into one entry under the new id: the old settings fill in what the new entry leaves
    /// unset, and the new id's value wins wherever both set a key. A severity shorthand counts as
    /// `severity: <level>`. The old key's comment block joins the new key's only when some old
    /// setting survives; an old value the engine cannot read is dropped with its comment.
    ///
    /// A list holding both ids keeps `newId` where it is and loses `oldId`, so no list repeats
    /// an id. The compatibility report's "Fix" and the migration assistant both rename here.
    mutating func renameRule(_ oldId: String, to newId: String) {
        guard oldId != newId else { return }
        let oldConfiguration = rules.removeValue(forKey: oldId)
        let oldNode = passthroughNodes.removeValue(forKey: oldId)
        let oldComment = comments.removeValue(forKey: oldId)
        if oldConfiguration != nil || oldNode != nil {
            var keepsOldComment = true
            if rules[newId] == nil && passthroughNodes[newId] == nil {
                rules[newId] = oldConfiguration
                passthroughNodes[newId] = oldNode
                if scalarShorthandRules.contains(oldId) { scalarShorthandRules.insert(newId) }
                if !keyOrder.contains(newId), let index = keyOrder.firstIndex(of: oldId) {
                    keyOrder[index] = newId
                }
            } else {
                let old = oldConfiguration ?? Self.severity(in: oldNode).map { RuleConfiguration(severity: $0) }
                keepsOldComment = old.map { mergeConfiguration($0, into: newId) } ?? false
            }
            if keepsOldComment, let oldComment {
                comments[newId] = comments[newId].map { $0 + "\n" + oldComment } ?? oldComment
            }
        }
        keyOrder.removeAll { $0 == oldId }
        scalarShorthandRules.remove(oldId)
        disabledRules = Self.renaming(oldId, to: newId, in: disabledRules)
        optInRules = Self.renaming(oldId, to: newId, in: optInRules)
        analyzerRules = Self.renaming(oldId, to: newId, in: analyzerRules)
        onlyRules = Self.renaming(oldId, to: newId, in: onlyRules)
    }

    /// Folds `old` into the configuration `newId` already has, the new value winning wherever
    /// both set a key, and returns whether any old setting survived. A new entry that is a
    /// severity shorthand becomes `old` with that severity; one the engine cannot read is kept.
    private mutating func mergeConfiguration(_ old: RuleConfiguration, into newId: String) -> Bool {
        var merged: RuleConfiguration
        if let existing = rules[newId] {
            merged = existing
        } else if let severity = Self.severity(in: passthroughNodes[newId]) {
            merged = RuleConfiguration(enabled: old.enabled, severity: severity)
        } else {
            return false
        }
        var survived = false
        if merged.severity == nil, let severity = old.severity {
            merged.severity = severity
            survived = true
        }
        for (key, value) in old.parameters ?? [:] where merged.parameters?[key] == nil {
            merged.parameters = (merged.parameters ?? [:]).merging([key: value]) { current, _ in current }
            survived = true
        }
        if survived {
            rules[newId] = merged
            passthroughNodes.removeValue(forKey: newId)
        }
        return survived
    }

    /// The severity a `rule: error` shorthand sets, read as SwiftLint reads it.
    private static func severity(in node: Node?) -> Severity? {
        node?.string.flatMap { Severity(rawValue: $0.lowercased()) }
    }

    /// `list` with `oldId` replaced by `newId` at its first occurrence, and every other
    /// occurrence of `oldId` dropped, as is `oldId` itself when `list` already holds `newId`.
    private static func renaming(_ oldId: String, to newId: String, in list: [String]?) -> [String]? {
        guard let list, list.contains(oldId) else { return list }
        var holdsNewId = list.contains(newId)
        return list.compactMap { ruleId in
            guard ruleId == oldId else { return ruleId }
            if holdsNewId { return nil }
            holdsNewId = true
            return newId
        }
    }
}
