//
//  YAMLConfigurationEngine+RuleLists.swift
//  SwiftLintRuleStudio
//
//  The four rule lists read the way SwiftLint reads them together: turning a rule
//  on or off in whichever mode the file is in, and repairing a file SwiftLint
//  rejects.
//

import Foundation

/// Which list turns a rule on when a configuration has no `only_rules`.
nonisolated public enum RuleListKind: Sendable, Equatable {
    /// On unless listed under `disabled_rules`.
    case standard
    /// Off unless listed under `opt_in_rules`.
    case optIn
    /// Off unless listed under `analyzer_rules`, and run only by `swiftlint analyze`.
    case analyzer

    /// SwiftLint reports every analyzer rule as opt-in too (`AnalyzerRule` refines
    /// `OptInRule`), so the analyzer flag decides first.
    nonisolated public init(isOptIn: Bool, isAnalyzer: Bool) {
        if isAnalyzer {
            self = .analyzer
        } else if isOptIn {
            self = .optIn
        } else {
            self = .standard
        }
    }

    nonisolated public init(_ rule: Rule) {
        self.init(isOptIn: rule.isOptIn, isAnalyzer: rule.isAnalyzer)
    }
}

/// How the rule lists combine, mirroring `Configuration.RulesMode.init` in SwiftLint:
///
/// - A non-empty `only_rules` puts the file in only mode. SwiftLint then runs
///   `only_rules ∪ analyzer_rules` and nothing else. An empty `only_rules` counts as no
///   list at all.
/// - In only mode a non-empty `opt_in_rules` or `disabled_rules` is an error. SwiftLint
///   ignores the whole file — `included`, `excluded` and every rule setting with it — and
///   falls back to its default configuration (a nested config aborts the run instead).
///   This is issue #83: the app used to write exactly that.
/// - An id listed under both `only_rules` and `analyzer_rules` runs once but prints
///   "listed multiple times".
/// - Every list is read through ``SwiftLintDeprecations/currentName(of:)``: a deprecated
///   alias such as `variable_name` names its rule (`identifier_name`) in any list. SwiftLint
///   checks for duplicates before mapping aliases, so an alias beside its rule's current name
///   prints no warning.
///
/// `nonisolated` because `RuleEnablementResolver` reads these from a nonisolated context,
/// and the package defaults everything else to the main actor.
nonisolated public extension YAMLConfigurationEngine.YAMLConfig {

    /// Whether SwiftLint runs this file in only mode.
    var usesOnlyRules: Bool {
        !(onlyRules ?? []).isEmpty
    }

    /// Whether SwiftLint rejects this file: `only_rules` together with a non-empty
    /// `opt_in_rules` or `disabled_rules`. (The parser reads the deprecated `enabled_rules`
    /// into ``optInRules``, as SwiftLint does, so it counts too.)
    var hasOnlyRulesConflict: Bool {
        usesOnlyRules && (!(optInRules ?? []).isEmpty || !(disabledRules ?? []).isEmpty)
    }

    /// Ids listed under both `only_rules` and `analyzer_rules`, in `only_rules` order.
    var rulesInOnlyAndAnalyzerRules: [String] {
        guard usesOnlyRules, let analyzerRules else { return [] }
        let analyzerIds = Set(analyzerRules)
        return Self.deduplicated((onlyRules ?? []).filter(analyzerIds.contains))
    }

    // MARK: - Turning rules on and off

    /// Turns `ruleId` on in the rule lists, in whichever mode the file is in.
    ///
    /// Touches the four lists only; the per-rule settings in ``rules`` stay the caller's.
    /// Starting from a file SwiftLint accepts, the result is one it accepts too:
    ///
    /// - In only mode the rule goes into `only_rules` — never `opt_in_rules`, which would
    ///   make SwiftLint reject the file. An analyzer rule goes into `analyzer_rules` instead,
    ///   which SwiftLint unions with `only_rules`. A rule already in either list is left
    ///   where it is rather than listed twice.
    /// - Otherwise an opt-in rule goes into `opt_in_rules` and an analyzer rule into
    ///   `analyzer_rules`. A standard rule needs no list.
    /// - Either way it leaves `disabled_rules`.
    ///
    /// A rule is matched under its deprecated aliases too: `disabled_rules: [if_let_shadowing]`
    /// loses that entry when `shorthand_optional_binding` is turned on, and a list already
    /// naming the rule by an alias counts as listing it.
    mutating func enableRule(_ ruleId: String, kind: RuleListKind) {
        Self.remove(ruleId, from: &disabledRules)
        switch kind {
        case .analyzer:
            if usesOnlyRules, Self.list(onlyRules, names: ruleId) { return }
            Self.append(ruleId, to: &analyzerRules)
        case .optIn, .standard:
            if usesOnlyRules {
                // SwiftLint runs analyzer_rules alongside only_rules, so an id already there
                // is on; listing it in both prints "listed multiple times".
                if !Self.list(analyzerRules, names: ruleId) {
                    Self.append(ruleId, to: &onlyRules)
                }
            } else if kind == .optIn {
                Self.append(ruleId, to: &optInRules)
            }
        }
    }

    /// Turns `ruleId` off in the rule lists. See ``disableRules(_:kind:)``.
    mutating func disableRule(_ ruleId: String, kind: RuleListKind) throws {
        try disableRules([ruleId]) { _ in kind }
    }

    /// Turns `ruleIds` off in the rule lists, in whichever mode the file is in.
    ///
    /// - In only mode each rule leaves `only_rules` and `analyzer_rules`, and nothing is
    ///   added to `disabled_rules`, which SwiftLint would reject.
    /// - Otherwise an opt-in or analyzer rule leaves its list, and a standard rule goes into
    ///   `disabled_rules`.
    ///
    /// The batch is checked as a whole before anything changes: it throws
    /// ``YAMLConfigError/wouldEmptyOnlyRules(ruleIds:)`` rather than empty `only_rules`.
    /// An empty `only_rules` is SwiftLint's default mode, so emptying the list would turn
    /// on every default rule — the opposite of turning the last ones off. Taking the rules
    /// one at a time would hit that partway through and leave the earlier ones on.
    ///
    /// Like ``enableRule(_:kind:)``, a rule's deprecated aliases count as the rule: each one
    /// leaves the lists with it, and a rule `disabled_rules` already names by an alias isn't
    /// added a second time.
    mutating func disableRules(_ ruleIds: [String], kind: (String) -> RuleListKind) throws {
        if usesOnlyRules {
            let removing = Set(ruleIds.map(SwiftLintDeprecations.currentName(of:)))
            let only = onlyRules ?? []
            if only.map(SwiftLintDeprecations.currentName(of:)).allSatisfy(removing.contains) {
                throw YAMLConfigError.wouldEmptyOnlyRules(ruleIds: only)
            }
        }
        for ruleId in ruleIds {
            Self.remove(ruleId, from: &onlyRules)
            Self.remove(ruleId, from: &analyzerRules)
            Self.remove(ruleId, from: &optInRules)
            if !usesOnlyRules, kind(ruleId) == .standard {
                Self.append(ruleId, to: &disabledRules)
            }
        }
    }

    // MARK: - Repair

    /// This configuration with its rule lists rewritten so SwiftLint accepts them.
    ///
    /// Changes nothing unless the file is in only mode. Then:
    ///
    /// 1. A conflict is folded into `only_rules`, the way SwiftLint itself combines a parent's
    ///    `only_rules` with a child config's lists: `only_rules ∪ opt_in_rules − disabled_rules`.
    ///    That also recovers what was meant in every file the app used to break — rules the
    ///    Rule Browser turned on landed only in `opt_in_rules`, and rules it turned off stayed
    ///    in `only_rules` and went into `disabled_rules`. `opt_in_rules` and `disabled_rules`
    ///    are then dropped, and their comment blocks move above
    ///    `only_rules`. `all` is not carried over: it names every opt-in rule only in default
    ///    mode. If every listed rule is also disabled, the fold would empty `only_rules` and
    ///    turn on every default rule, so `only_rules` is kept as it was instead.
    /// 2. An id listed under both `only_rules` and `analyzer_rules` keeps only its
    ///    `analyzer_rules` entry — unless that would empty `only_rules`, in which case it keeps
    ///    the `only_rules` one. SwiftLint runs the union, so neither changes what runs.
    ///
    /// Idempotent, never leaves a conflict, and never empties a non-empty `only_rules`.
    ///
    /// The fold reads a deprecated alias as its rule, as SwiftLint does: `disabled_rules:
    /// [variable_name]` takes `identifier_name` out of `only_rules`, and an alias in
    /// `opt_in_rules` of a rule `only_rules` already lists isn't added twice. Step 2 compares
    /// ids as written, as SwiftLint's "listed multiple times" warning does.
    func normalizedRuleLists() -> Self {
        guard usesOnlyRules else { return self }
        var result = self
        if hasOnlyRulesConflict {
            result.foldConflictIntoOnlyRules()
        }
        result.removeAnalyzerRulesFromOnlyRules()
        return result
    }

    private mutating func foldConflictIntoOnlyRules() {
        let disabled = Set((disabledRules ?? []).map(SwiftLintDeprecations.currentName(of:)))
        let isDisabled = { disabled.contains(SwiftLintDeprecations.currentName(of: $0)) }
        let folded = Self.deduplicatedByRule((onlyRules ?? []) + (optInRules ?? []).filter { $0 != "all" })
            .filter { !isDisabled($0) }
        if !folded.isEmpty {
            onlyRules = folded
            // A disabled analyzer rule has to leave `analyzer_rules` too, or it keeps running.
            if let remaining = analyzerRules?.filter({ !isDisabled($0) }) {
                analyzerRules = remaining.isEmpty ? nil : remaining
            }
        }

        var blocks = ["opt_in_rules", "disabled_rules"].compactMap { comments[$0] }
        if !blocks.isEmpty {
            if let own = comments["only_rules"] {
                blocks.insert(own, at: 0)
            }
            comments["only_rules"] = blocks.joined(separator: "\n")
        }
        optInRules = nil
        disabledRules = nil
    }

    private mutating func removeAnalyzerRulesFromOnlyRules() {
        let duplicated = Set(rulesInOnlyAndAnalyzerRules)
        guard !duplicated.isEmpty else { return }
        let remaining = (onlyRules ?? []).filter { !duplicated.contains($0) }
        if remaining.isEmpty {
            let analyzerOnly = (analyzerRules ?? []).filter { !duplicated.contains($0) }
            analyzerRules = analyzerOnly.isEmpty ? nil : analyzerOnly
        } else {
            onlyRules = remaining
        }
    }

    // MARK: - Helpers

    /// Whether `entry` names the same rule as `ruleId`, under its current name or a deprecated
    /// alias.
    private static func entry(_ entry: String, names ruleId: String) -> Bool {
        SwiftLintDeprecations.currentName(of: entry) == SwiftLintDeprecations.currentName(of: ruleId)
    }

    private static func list(_ list: [String]?, names ruleId: String) -> Bool {
        list?.contains { entry($0, names: ruleId) } == true
    }

    /// Appends `ruleId` unless the list already names the rule, by any name.
    private static func append(_ ruleId: String, to list: inout [String]?) {
        guard !Self.list(list, names: ruleId) else { return }
        list = (list ?? []) + [ruleId]
    }

    /// Removes every entry naming `ruleId`, aliases included, dropping the key when the list
    /// empties — a list is absent or holds something. A list that doesn't name the rule is
    /// left exactly as it was.
    private static func remove(_ ruleId: String, from list: inout [String]?) {
        guard var current = list, Self.list(current, names: ruleId) else { return }
        current.removeAll { entry($0, names: ruleId) }
        list = current.isEmpty ? nil : current
    }

    /// `ids` with each rule kept at its first entry, whatever name later ones use.
    private static func deduplicatedByRule(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids.filter { seen.insert(SwiftLintDeprecations.currentName(of: $0)).inserted }
    }

    private static func deduplicated(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
    }
}

// MARK: - File marker (satisfies file_name lint rule)

extension YAMLConfigurationEngine {}
