//
//  ConfigImportServicePropertyLawTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Property laws for `ConfigImportService.fetchAndPreview`'s validation: an
//  imported configuration is warned empty exactly when it names no rule.
//  Mutation testing left five of the file's seven mutants alive, all in that
//  condition. The one example test imported an empty config, so a condition that
//  warned every config, or warned none, passed it.
//
//  The condition had also dropped a member. It tested the rules dictionary and
//  three of the four rule lists, but not `analyzerRules`, so a config defining
//  only analyzer rules was warned "Configuration appears empty – no rules
//  defined." SwiftProjectLint's Parallel List Drift found it by comparison with
//  the two other enumerations of the same fields. They are now one:
//  `YAMLConfig.ruleIds`.
//
//  The oracle is the set of rules the generator placed, not `ruleIds`, so these
//  laws check that member too.
//

import Foundation
import PropertyBased
@testable import SwiftLintRuleStudioCore
import Testing

/// A generated configuration, kept to primitives so it can cross the generator
/// boundary — `YAMLConfig` is main-actor-isolated.
private struct ImportSpec: Sendable {
    /// Each configured rule: an index into the vocabulary, and which field holds it.
    let rules: [Placement]
    /// Paths and a reporter: fields that name no rule, so a config holding only
    /// them is still empty.
    let excludesPaths: Bool
    let setsReporter: Bool

    struct Placement: Sendable, Hashable {
        let rule: Int
        let field: Int
    }
}

/// Hands back the YAML it was built with.
private struct FixedFetcher: URLConfigFetcherProtocol {
    let yaml: String

    func fetchConfig(from _: URL) throws -> String { yaml }

    func validateURL(_: URL) -> URLValidationResult { .valid }
}

@MainActor
@Suite("Config import service property laws")
struct ConfigImportServicePropertyLawTests {

    private static let emptyWarning = "Configuration appears empty - no rules defined."
    private static let vocabulary = ["line_length", "force_cast", "unused_import", "explicit_self", "todo"]
    private static let source = URL(fileURLWithPath: "/imported/.swiftlint.yml")

    // MARK: - Generators

    private static func specGenerator() -> Generator<ImportSpec, some SendableSequenceType> {
        let placement = zip(
            Gen<Int>.int(in: 0 ... (vocabulary.count - 1)),
            Gen<Int>.int(in: 0...4)
        ).map { ImportSpec.Placement(rule: $0, field: $1) }
        return zip(placement.array(of: 0...4), Gen<Bool>.bool, Gen<Bool>.bool)
            .map { ImportSpec(rules: $0, excludesPaths: $1, setsReporter: $2) }
    }

    // MARK: - Construction

    /// The configuration `spec` describes. Field 0 is the rules dictionary; the
    /// rest are the four rule lists, each absent rather than empty.
    ///
    /// A rule configuration carries a severity: one with no setting is written as
    /// nothing, by design — SwiftLint gives an empty mapping no meaning — so it
    /// would not survive the YAML the import fetches.
    private static func config(for spec: ImportSpec) -> YAMLConfigurationEngine.YAMLConfig {
        var config = YAMLConfigurationEngine.YAMLConfig()
        var lists: [[String]] = Array(repeating: [], count: 4)
        for placement in spec.rules {
            let rule = vocabulary[placement.rule]
            if placement.field == 0 {
                config.rules[rule] = RuleConfiguration(enabled: true, severity: .warning)
            } else if !lists[placement.field - 1].contains(rule) {
                lists[placement.field - 1].append(rule)
            }
        }
        config.disabledRules = lists[0].isEmpty ? nil : lists[0]
        config.optInRules = lists[1].isEmpty ? nil : lists[1]
        config.analyzerRules = lists[2].isEmpty ? nil : lists[2]
        config.onlyRules = lists[3].isEmpty ? nil : lists[3]
        config.excluded = spec.excludesPaths ? ["Pods"] : nil
        config.reporter = spec.setsReporter ? "json" : nil
        return config
    }

    private static func placedRules(_ spec: ImportSpec) -> Set<String> {
        Set(spec.rules.map { vocabulary[$0.rule] })
    }

    private static func preview(of config: YAMLConfigurationEngine.YAMLConfig) async throws -> ConfigImportPreview {
        let yaml = try YAMLConfigurationEngine.serialize(config)
        return try await ConfigImportService(fetcher: FixedFetcher(yaml: yaml))
            .fetchAndPreview(from: source, currentConfigPath: nil)
    }

    // MARK: - Laws

    @Test("an import is warned empty exactly when it names no rule, and at most once")
    func emptyWarningFollowsTheRules() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let preview = try await Self.preview(of: Self.config(for: spec))
            let expected = Self.placedRules(spec).isEmpty ? [Self.emptyWarning] : []
            #expect(preview.validationErrors == expected)
        }
    }

    @Test("the parsed config names exactly the rules the import placed, in any field")
    func ruleIdsAreThePlacedRules() async {
        await propertyCheck(input: Self.specGenerator()) { spec in
            let preview = try await Self.preview(of: Self.config(for: spec))
            #expect(preview.parsedConfig.ruleIds == Self.placedRules(spec))
        }
    }

    // MARK: - The dropped member, pinned

    @Test("a config defining only analyzer rules is not warned empty")
    func analyzerRulesAloneAreRules() async throws {
        var config = YAMLConfigurationEngine.YAMLConfig()
        config.analyzerRules = ["unused_import"]
        let preview = try await Self.preview(of: config)
        #expect(preview.validationErrors.isEmpty)
    }
}
