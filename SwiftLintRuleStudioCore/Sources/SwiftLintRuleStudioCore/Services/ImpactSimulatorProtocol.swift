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
    /// Whether the rule is an analyzer rule.
    public var isAnalyzer: Bool
    /// Optional parameter overrides applied to the rule's configuration.
    public var parameterOverrides: [String: AnyCodable]?

    /// Creates options describing how a single rule should be simulated.
    public init(
        isOptIn: Bool = false,
        isAnalyzer: Bool = false,
        parameterOverrides: [String: AnyCodable]? = nil
    ) {
        self.isOptIn = isOptIn
        self.isAnalyzer = isAnalyzer
        self.parameterOverrides = parameterOverrides
    }
}

/// Classifies which rule IDs in a batch are opt-in or analyzer rules.
public struct RuleClassification {
    /// Rule IDs that are opt-in rules.
    public var optInRuleIds: Set<String>
    /// Rule IDs that are analyzer rules.
    public var analyzerRuleIds: Set<String>

    /// Creates a classification of opt-in and analyzer rule IDs for a batch.
    public init(optInRuleIds: Set<String> = [], analyzerRuleIds: Set<String> = []) {
        self.optInRuleIds = optInRuleIds
        self.analyzerRuleIds = analyzerRuleIds
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
