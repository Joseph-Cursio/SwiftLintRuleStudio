//
//  ImpactSimulator.swift
//  SwiftLintRuleStudio
//
//  Service for simulating rule violations without actually enabling rules
//

import Foundation

/// Result of simulating a rule's impact
public struct RuleImpactResult: Sendable, Identifiable {
    nonisolated public let ruleId: String
    nonisolated public var id: String { ruleId }
    nonisolated public let violationCount: Int
    nonisolated public let violations: [Violation]
    nonisolated public let affectedFiles: Set<String>
    nonisolated public let simulationDuration: TimeInterval

    public init(
        ruleId: String,
        violationCount: Int,
        violations: [Violation],
        affectedFiles: Set<String>,
        simulationDuration: TimeInterval
    ) {
        self.ruleId = ruleId
        self.violationCount = violationCount
        self.violations = violations
        self.affectedFiles = affectedFiles
        self.simulationDuration = simulationDuration
    }

    nonisolated public var hasViolations: Bool {
        violationCount > 0
    }

    nonisolated public var isSafe: Bool {
        violationCount == 0
    }
}

/// Result of batch simulation
public struct BatchSimulationResult: Sendable {
    nonisolated public let results: [RuleImpactResult]
    nonisolated public let totalDuration: TimeInterval
    nonisolated public let completedAt: Date

    public init(results: [RuleImpactResult], totalDuration: TimeInterval, completedAt: Date) {
        self.results = results
        self.totalDuration = totalDuration
        self.completedAt = completedAt
    }

    nonisolated public var safeRules: [RuleImpactResult] {
        results.filter(\.isSafe)
    }

    nonisolated public var rulesWithViolations: [RuleImpactResult] {
        results.filter(\.hasViolations)
    }
}

/// Service for simulating the impact of enabling rules
public class ImpactSimulator: ImpactSimulatorProtocol {

    // MARK: - Properties

    private let swiftLintCLI: SwiftLintCLIProtocol
    private let workspaceBuilder: SimulationWorkspaceBuilder

    // MARK: - Initialization

    /// Creates a simulator backed by the given SwiftLint CLI and file manager
    public init(swiftLintCLI: SwiftLintCLIProtocol, fileManager: FileManager = .default) {
        self.swiftLintCLI = swiftLintCLI
        self.workspaceBuilder = SimulationWorkspaceBuilder(fileManager: fileManager)
    }

    // MARK: - Single Rule Simulation

    /// Simulate the impact of enabling a single rule
    /// - Parameters:
    ///   - ruleId: The rule identifier to simulate
    ///   - workspace: The workspace to analyze
    ///   - baseConfigPath: Path to the base SwiftLint configuration
    /// - Returns: Impact result with violation count and details
    public func simulateRule(
        ruleId: String,
        workspace: Workspace,
        baseConfigPath: URL?,
        options: RuleSimulationOptions = RuleSimulationOptions()
    ) async throws -> RuleImpactResult {
        // Mirror the workspace once, enable the rule everywhere, lint the mirror.
        let shadow = try workspaceBuilder.makeWorkspace(for: workspace, baseConfigPath: baseConfigPath)
        defer { shadow.cleanup() }

        return try await measureRule(
            ruleId,
            on: shadow,
            isOptIn: options.isOptIn,
            isAnalyzer: options.isAnalyzer,
            parameterOverrides: options.parameterOverrides
        )
    }

    /// Enables `ruleId` across the mirror's configs, lints it, and tallies the
    /// violations attributable to that rule. Shared by single and batch paths so
    /// a batch audit can reuse one mirror across many rules.
    private func measureRule(
        _ ruleId: String,
        on shadow: SimulationWorkspace,
        isOptIn: Bool,
        isAnalyzer: Bool,
        parameterOverrides: [String: AnyCodable]?
    ) async throws -> RuleImpactResult {
        let startTime = Date.now

        try shadow.applyRule(
            ruleId,
            isOptIn: isOptIn,
            isAnalyzer: isAnalyzer,
            parameterOverrides: parameterOverrides
        )

        // `.effective` mode with `cwd` = the mirror root: SwiftLint discovers the
        // mirror's (rule-enabled) root and nested configs itself. `configPath` is
        // deliberately nil — passing `--config` would disable nested resolution.
        let lintData = try await swiftLintCLI.executeLintCommand(
            configPath: nil,
            workspacePath: shadow.root
        )

        // Paths come back rooted at the mirror; stripping that prefix yields the
        // same workspace-relative paths the real workspace would produce.
        let allViolations = try parseViolations(from: lintData, workspacePath: shadow.root)
        let ruleViolations = allViolations.filter { $0.ruleID == ruleId }
        let affectedFiles = Set(ruleViolations.map(\.filePath))

        return RuleImpactResult(
            ruleId: ruleId,
            violationCount: ruleViolations.count,
            violations: ruleViolations,
            affectedFiles: affectedFiles,
            simulationDuration: Date.now.timeIntervalSince(startTime)
        )
    }

    // MARK: - Batch Simulation

    /// Simulate the impact of enabling multiple rules
    /// - Parameters:
    ///   - ruleIds: Array of rule identifiers to simulate
    ///   - workspace: The workspace to analyze
    ///   - baseConfigPath: Path to the base SwiftLint configuration
    ///   - progressHandler: Optional callback for progress updates
    /// - Returns: Batch simulation result with all rule impacts
    public func simulateRules(
        ruleIds: [String],
        workspace: Workspace,
        baseConfigPath: URL?,
        classification: RuleClassification = RuleClassification(),
        progressHandler: ((Int, Int, String) -> Void)? = nil
    ) async throws -> BatchSimulationResult {
        let startTime = Date.now
        var results: [RuleImpactResult] = []

        // Mirror the workspace once; each rule only rewrites the mirror's configs.
        let shadow = try workspaceBuilder.makeWorkspace(for: workspace, baseConfigPath: baseConfigPath)
        defer { shadow.cleanup() }

        for (index, ruleId) in ruleIds.enumerated() {
            // Report progress
            progressHandler?(index, ruleIds.count, ruleId)

            do {
                let result = try await measureRule(
                    ruleId,
                    on: shadow,
                    isOptIn: classification.optInRuleIds.contains(ruleId),
                    isAnalyzer: classification.analyzerRuleIds.contains(ruleId),
                    parameterOverrides: nil
                )
                results.append(result)
            } catch {
                // If simulation fails for a rule, create a result with error indication
                // We'll use a violation count of -1 to indicate error
                let errorResult = RuleImpactResult(
                    ruleId: ruleId,
                    violationCount: -1, // Error indicator
                    violations: [],
                    affectedFiles: [],
                    simulationDuration: 0
                )
                results.append(errorResult)
            }
        }

        let duration = Date.now.timeIntervalSince(startTime)

        return BatchSimulationResult(
            results: results,
            totalDuration: duration,
            completedAt: Date.now
        )
    }

    /// Find all disabled rules with zero violations (safe to enable)
    /// - Parameters:
    ///   - workspace: The workspace to analyze
    ///   - baseConfigPath: Path to the base SwiftLint configuration
    ///   - disabledRuleIds: Array of disabled rule identifiers to check
    ///   - progressHandler: Optional callback for progress updates
    /// - Returns: Array of rule IDs that are safe to enable (zero violations)
    public func findSafeRules(
        workspace: Workspace,
        baseConfigPath: URL?,
        disabledRuleIds: [String],
        classification: RuleClassification = RuleClassification(),
        progressHandler: ((Int, Int, String) -> Void)? = nil
    ) async throws -> [String] {
        let batchResult = try await simulateRules(
            ruleIds: disabledRuleIds,
            workspace: workspace,
            baseConfigPath: baseConfigPath,
            classification: classification,
            progressHandler: progressHandler
        )

        // Filter to rules with zero violations (and no errors)
        return batchResult.safeRules
            .filter { $0.violationCount >= 0 } // Exclude error cases
            .map(\.ruleId)
    }

    // MARK: - Helper Methods

    /// Parse violations from SwiftLint JSON output
    private func parseViolations(from data: Data, workspacePath: URL) throws -> [Violation] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var violations: [Violation] = []

        for item in json {
            guard let ruleId = item["rule_id"] as? String,
                  let reason = item["reason"] as? String,
                  let severityString = item["severity"] as? String,
                  let file = item["file"] as? String else {
                continue
            }

            // Parse line and column
            let line = item["line"] as? Int ?? 0
            let column = item["column"] as? Int ?? 0

            // Parse severity
            let severity = Severity(rawValue: severityString.lowercased()) ?? .warning

            // Convert file path to relative path
            let fullPath = URL(fileURLWithPath: file)
            let relativePath: String
            if fullPath.path.hasPrefix(workspacePath.path) {
                let relative = fullPath.path.dropFirst(workspacePath.path.count)
                relativePath = relative.hasPrefix("/") ? String(relative.dropFirst()) : String(relative)
            } else {
                relativePath = file
            }

            let violation = Violation(
                ruleID: ruleId,
                filePath: relativePath,
                line: line,
                severity: severity,
                message: reason,
                id: UUID(),
                column: column,
                detectedAt: Date.now
            )

            violations.append(violation)
        }

        return violations
    }
}
