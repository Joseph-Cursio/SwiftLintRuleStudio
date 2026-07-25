//
//  ConfigRoundTripPropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for `serialize` ↔ `parse` — candidate §1, the highest-value law
//  in docs/pbt-candidates.md and the one that was blocked longest.
//
//  It was blocked on a refactor, not on effort: there was no app-side
//  `parse(String) -> YAMLConfig`, because `load()` read from disk and mutated
//  `self`. Extracting the pure half is what made this writable, and it is the
//  case the roadmap flagged as PBT-driven — the property specified the refactor.
//
//  Two laws, and the second is the stronger one:
//
//    A. parse(serialize(config)) ≈ config   — on the modeled fields
//    B. serialize(parse(serialize(config))) == serialize(config)
//
//  B needs no field-by-field model at all: it says a save/reload cycle is a
//  fixed point on the *text*, so it catches layout regressions (block-sequence
//  indentation, comment reinsertion, key order) that A's `≈` deliberately
//  ignores. A is still worth stating because it names which fields carry
//  meaning, and it fails more legibly.
//
//  `≈` is not equality, and the gap is a real migration rather than sloppiness:
//  a rule with `enabled == false` is emitted only via `disabled_rules` (SwiftLint
//  has no per-rule disable), so it comes back in `disabledRules` and absent from
//  `rules`. The law models that rather than demanding byte-identity.
//
//  Generators aim at the hazards the roadmap listed: scalar shorthand
//  (`line_length: 120` must not re-emit as `{warning: 120}`), numeric-looking
//  string parameters (which must stay quoted, or SwiftLint rejects the file),
//  bool-vs-int classification, and disabled rules that also carry a severity.
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

/// One generated rule entry, kept to primitives so it can cross the generator
/// boundary — `YAMLConfig` is main-actor-isolated.
private struct RuleSpec: Sendable {
    let nameIndex: Int
    let enabled: Bool
    /// 0 = none, 1 = warning, 2 = error.
    let severityIndex: Int
    /// 0 = none, 1 = int, 2 = string, 3 = numeric-looking string, 4 = bool.
    let parameterKind: Int
    /// Emit as the bare-scalar shorthand (`line_length: 120`).
    let shorthand: Bool
}

private struct ConfigSpec: Sendable {
    let rules: [RuleSpec]
    let disabledIndices: [Int]
    let optInIndices: [Int]
    let analyzerIndices: [Int]
    let setsOnlyRules: Bool
    let setsIncluded: Bool
    let setsExcluded: Bool
    let setsReporter: Bool
}

@MainActor
@Suite("config serialize ↔ parse property laws")
struct ConfigRoundTripPropertyLawTests {

    /// Four names, shared by the rule mappings and the membership lists, so the
    /// two collide on most trials. A wide alphabet would never produce a rule
    /// that is both configured and listed — which is exactly where the emission
    /// paths interact.
    nonisolated private static let ruleNames = ["line_length", "todo", "force_cast", "empty_count"]

    nonisolated private static func specGenerator() -> Generator<ConfigSpec, some SendableSequenceType> {
        let ruleIndex = Gen<Int>.int(in: 0 ... (ruleNames.count - 1))
        let rule = zip(
            ruleIndex,
            Gen<Bool>.bool,
            Gen<Int>.int(in: 0...2),
            Gen<Int>.int(in: 0...4),
            Gen<Bool>.bool
        ).map { nameIndex, enabled, severityIndex, parameterKind, shorthand in
            RuleSpec(
                nameIndex: nameIndex,
                enabled: enabled,
                severityIndex: severityIndex,
                parameterKind: parameterKind,
                shorthand: shorthand
            )
        }

        return zip(
            rule.array(of: 0...4),
            ruleIndex.array(of: 0...3),
            ruleIndex.array(of: 0...3),
            ruleIndex.array(of: 0...2),
            Gen<Bool>.bool,
            Gen<Bool>.bool,
            Gen<Bool>.bool,
            Gen<Bool>.bool
        ).map { rules, disabled, optIn, analyzer, only, included, excluded, reporter in
            ConfigSpec(
                rules: rules,
                disabledIndices: disabled,
                optInIndices: optIn,
                analyzerIndices: analyzer,
                setsOnlyRules: only,
                setsIncluded: included,
                setsExcluded: excluded,
                setsReporter: reporter
            )
        }
    }

    // MARK: - Construction

    private func makeConfig(from spec: ConfigSpec) -> YAMLConfigurationEngine.YAMLConfig {
        var config = YAMLConfigurationEngine.YAMLConfig()

        for rule in spec.rules {
            let name = Self.ruleNames[rule.nameIndex]
            let severity: Severity? = [nil, .warning, .error][rule.severityIndex]
            var parameters: [String: AnyCodable]?
            switch rule.parameterKind {
            case 1: parameters = ["warning": AnyCodable(120)]
            case 2: parameters = ["kind": AnyCodable("alpha")]
            case 3: parameters = ["kind": AnyCodable("120")]
            case 4: parameters = ["flag": AnyCodable(true)]
            default: parameters = nil
            }
            if rule.shorthand {
                // The shorthand only exists for a lone integer `warning`.
                parameters = ["warning": AnyCodable(120)]
                config.scalarShorthandRules.insert(name)
            }
            config.rules[name] = RuleConfiguration(
                enabled: rule.enabled,
                severity: severity,
                parameters: parameters
            )
        }

        let names = { (indices: [Int]) -> [String]? in
            let list = indices.map { Self.ruleNames[$0] }
            return list.isEmpty ? nil : Array(Set(list)).sorted()
        }
        config.disabledRules = names(spec.disabledIndices)
        config.optInRules = names(spec.optInIndices)
        config.analyzerRules = names(spec.analyzerIndices)
        config.onlyRules = spec.setsOnlyRules ? ["todo"] : nil
        config.included = spec.setsIncluded ? ["Sources"] : nil
        config.excluded = spec.setsExcluded ? ["Pods", "Carthage"] : nil
        config.reporter = spec.setsReporter ? "json" : nil
        return config
    }

    private func makeEngine() -> YAMLConfigurationEngine {
        YAMLConfigurationEngine(configPath: URL(fileURLWithPath: "/nonexistent/.swiftlint.yml"))
    }

    // MARK: - Reference definition: what a rule actually emits

    /// True when `ruleId` is written as the bare-scalar shorthand
    /// (`line_length: 120`). Requires the layout flag *and* the exact shape the
    /// shorthand can express: no severity, and a lone integer `warning`.
    /// A config that asks for the shorthand on any other shape degrades to a
    /// mapping — which is why the generator is allowed to ask for it anyway.
    private static func emitsScalarShorthand(
        _ ruleId: String,
        in config: YAMLConfigurationEngine.YAMLConfig
    ) -> Bool {
        guard config.scalarShorthandRules.contains(ruleId),
              let rule = config.rules[ruleId],
              rule.severity == nil,
              let parameters = rule.parameters,
              parameters.count == 1,
              parameters["warning"]?.value is Int else {
            return false
        }
        return true
    }

    /// The rule keys that survive as `rules` entries. A rule emits nothing at
    /// all when it carries neither a severity nor parameters — there is no YAML
    /// to write for it — so it is absent after a round-trip. Disabled rules
    /// migrate to `disabled_rules` instead.
    private static func emittedRuleKeys(
        in config: YAMLConfigurationEngine.YAMLConfig
    ) -> Set<String> {
        Set(config.rules.filter { ruleId, rule in
            guard rule.enabled else { return false }
            if emitsScalarShorthand(ruleId, in: config) { return true }
            return rule.severity != nil || !(rule.parameters?.isEmpty ?? true)
        }.keys)
    }

    // MARK: - Law A — the modeled fields survive

    @Test("a config survives serialize → parse on its modeled fields")
    func modeledFieldsRoundTrip() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let engine = makeEngine()
            let config = makeConfig(from: spec)
            let back = try engine.parse(try engine.serialize(config))

            // A rule marked `enabled == false` migrates into `disabled_rules`:
            // SwiftLint has no per-rule disable, so that is the only way to say
            // it. Everything still enabled stays a rule mapping.
            let disabledByFlag = Set(config.rules.filter { !$0.value.enabled }.keys)
            let expectedDisabled = Set(config.disabledRules ?? []).union(disabledByFlag)
            let expectedRuleKeys = Self.emittedRuleKeys(in: config)

            #expect(Set(back.disabledRules ?? []) == expectedDisabled)
            #expect(Set(back.rules.keys) == expectedRuleKeys)

            // The lists that are plain sets of identifiers.
            #expect(Set(back.optInRules ?? []) == Set(config.optInRules ?? []))
            #expect(Set(back.analyzerRules ?? []) == Set(config.analyzerRules ?? []))
            #expect(Set(back.onlyRules ?? []) == Set(config.onlyRules ?? []))

            // Ordered, root-level values come back verbatim.
            #expect(back.included == config.included)
            #expect(back.excluded == config.excluded)
            #expect(back.reporter == config.reporter)

            // Per-rule detail survives for every rule that stayed a mapping.
            for key in expectedRuleKeys {
                #expect(back.rules[key]?.severity == config.rules[key]?.severity)
                #expect(back.rules[key]?.parameters == config.rules[key]?.parameters)
                #expect(back.rules[key]?.enabled == true)
            }

            // The scalar shorthand is a layout fact the parser recovers from the
            // emitted text — so it comes back exactly for the rules actually
            // written that way, not for every rule that asked.
            let expectedShorthand = Set(expectedRuleKeys.filter { Self.emitsScalarShorthand($0, in: config) })
            #expect(back.scalarShorthandRules == expectedShorthand)
        }
    }

    // MARK: - Law B — the save/reload cycle is a fixed point on the text

    @Test("serializing a parsed config reproduces the text it was parsed from")
    func serializeIsAFixedPointThroughParse() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let engine = makeEngine()
            let once = try engine.serialize(makeConfig(from: spec))
            let twice = try engine.serialize(try engine.parse(once))

            // Stronger than law A: no field model, so nothing can be forgotten
            // from the comparison. Layout counts — indentation, key order and
            // comment placement all have to land in the same place.
            #expect(twice == once)
        }
    }

    @Test("opening and saving a hand-written config does not rewrite it")
    func handWrittenConfigIsAFixedPoint() throws {
        // Law B above only ranges over the IMAGE of `serialize`, which leaves a
        // real blind spot: a layout regression that changes every emission
        // equally still round-trips against itself. Dropping
        // `indentBlockSequences` is exactly that mutant, and it survives law B.
        //
        // This is the user-facing statement — open a conventionally formatted
        // `.swiftlint.yml`, save it without edits, and the file is untouched.
        // It pins the layout choices (two-space sequence indentation, comment
        // placement, key order) against the text a person actually wrote.
        let source = """
        # Which files we skip
        excluded:
          - Pods
          - Carthage
        disabled_rules:
          - todo
          - force_cast
        opt_in_rules:
          - empty_count
        line_length: 120
        custom_rules:
          my_rule:
            regex: "foo"
        reporter: json

        """
        let engine = makeEngine()
        #expect(try engine.serialize(try engine.parse(source)) == source)
    }

    // MARK: - Identity and passthrough

    @Test("the empty config is the identity element")
    func emptyConfigRoundTrips() throws {
        let engine = makeEngine()
        let yaml = try engine.serialize(YAMLConfigurationEngine.YAMLConfig())
        #expect(yaml == "{}\n")

        let back = try engine.parse(yaml)
        #expect(back.rules.isEmpty)
        #expect(back.disabledRules == nil)
        #expect(back.excluded == nil)
        #expect(back.keyOrder.isEmpty)
    }

    @Test("unmodeled top-level keys and their comments survive a round-trip")
    func passthroughKeysSurvive() throws {
        // `custom_rules`, `warning_threshold` and `strict` are not modeled
        // fields — they ride through as `passthroughNodes`, and dropping them
        // would silently rewrite a user's file on save.
        let source = """
        # leading comment
        warning_threshold: 10
        strict: true
        custom_rules:
          my_rule:
            regex: "foo"
        disabled_rules:
          - todo
        """
        let engine = makeEngine()
        let parsed = try engine.parse(source)

        #expect(Set(parsed.passthroughNodes.keys) == ["warning_threshold", "strict", "custom_rules"])
        #expect(parsed.comments["warning_threshold"] == "# leading comment")

        let emitted = try engine.serialize(parsed)
        #expect(emitted.contains("warning_threshold: 10"))
        #expect(emitted.contains("strict: true"))
        #expect(emitted.contains("regex: \"foo\""))
        #expect(emitted.contains("# leading comment"))
        #expect(try engine.serialize(try engine.parse(emitted)) == emitted)
    }

    @Test("a numeric-looking string parameter stays a string")
    func numericLookingStringsStayQuoted() throws {
        // If `"120"` re-emits unquoted it parses back as Int, and SwiftLint
        // rejects a config whose string option arrived as a number.
        let engine = makeEngine()
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.rules["custom"] = RuleConfiguration(
            enabled: true, severity: nil, parameters: ["kind": AnyCodable("120")]
        )

        let yaml = try engine.serialize(config)
        #expect(yaml.contains("'120'") || yaml.contains("\"120\""))
        #expect(try engine.parse(yaml).rules["custom"]?.parameters == ["kind": AnyCodable("120")])
    }
}
