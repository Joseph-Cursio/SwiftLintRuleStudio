//
//  ImpactSimulatorProtocol.swift
//  SwiftLintRuleStudio
//
//  Abstraction over the rule-impact simulator.
//

import Foundation

/// Options controlling how a single rule is simulated.
public struct RuleSimulationOptions {
    /// Whether the rule is opt-in (must be explicitly enabled).
    public var isOptIn: Bool
    /// Whether the rule is an analyzer rule. Linting never runs one, so it is reported as
    /// unmeasurable rather than simulated.
    public var isAnalyzer: Bool
    /// Whether the rule needs SourceKit and this edition can't load it. Such a rule lints
    /// clean whatever the code holds, so it is reported as unmeasurable rather than simulated.
    public var isSourceKitUnavailable: Bool
    /// Optional parameter overrides applied to the rule's configuration.
    public var parameterOverrides: [String: AnyCodable]?

    /// Creates options describing how a single rule should be simulated.
    public init(
        isOptIn: Bool = false,
        isAnalyzer: Bool = false,
        isSourceKitUnavailable: Bool = false,
        parameterOverrides: [String: AnyCodable]? = nil
    ) {
        self.isOptIn = isOptIn
        self.isAnalyzer = isAnalyzer
        self.isSourceKitUnavailable = isSourceKitUnavailable
        self.parameterOverrides = parameterOverrides
    }

    /// Options for simulating `rule` in an edition with `capabilities`.
    ///
    /// Takes the capabilities rather than defaulting them, so a caller can't forget that a
    /// SourceKit rule can't be measured where SourceKit can't load.
    public init(
        rule: Rule,
        capabilities: Set<AppCapability>,
        parameterOverrides: [String: AnyCodable]? = nil
    ) {
        self.init(
            isOptIn: rule.isOptIn,
            isAnalyzer: rule.isAnalyzer,
            isSourceKitUnavailable: rule.isUnavailableForLinting(capabilities: capabilities),
            parameterOverrides: parameterOverrides
        )
    }
}

/// Classifies the rule IDs in a batch: which are opt-in or analyzer rules, and which need
/// SourceKit where it can't load.
public struct RuleClassification {
    /// Rule IDs that are opt-in rules.
    public var optInRuleIds: Set<String>
    /// Rule IDs that are analyzer rules.
    public var analyzerRuleIds: Set<String>
    /// Rule IDs that need SourceKit, which this edition can't load. They are reported as
    /// unmeasurable rather than simulated.
    public var sourceKitUnavailableRuleIds: Set<String>

    /// Creates a classification of the rule IDs in a batch.
    public init(
        optInRuleIds: Set<String> = [],
        analyzerRuleIds: Set<String> = [],
        sourceKitUnavailableRuleIds: Set<String> = []
    ) {
        self.optInRuleIds = optInRuleIds
        self.analyzerRuleIds = analyzerRuleIds
        self.sourceKitUnavailableRuleIds = sourceKitUnavailableRuleIds
    }
}

/// Abstraction over the rule-impact simulator so callers — and tests — can
/// depend on the simulation capability without binding to the concrete class
/// or subclassing it to provide a test double.
public protocol ImpactSimulatorProtocol: AnyObject {
    /// Simulate the impact of enabling a single rule.
    func simulateRule(
        ruleId: String,
        workspace: Workspace,
        baseConfigPath: URL?,
        options: RuleSimulationOptions
    ) async throws -> RuleImpactResult

    /// Simulate the impact of enabling multiple rules.
    ///
    /// Returns one result per rule. A rule that fails to simulate, or that linting cannot
    /// measure, still gets a result — one whose `measurement` says so, never a count of 0.
    func simulateRules(
        ruleIds: [String],
        workspace: Workspace,
        baseConfigPath: URL?,
        classification: RuleClassification,
        progressHandler: ((Int, Int, String) -> Void)?
    ) async throws -> BatchSimulationResult

    /// Find disabled rules that produce zero violations (safe to enable).
    func findSafeRules(
        workspace: Workspace,
        baseConfigPath: URL?,
        disabledRuleIds: [String],
        classification: RuleClassification,
        progressHandler: ((Int, Int, String) -> Void)?
    ) async throws -> [String]
}
