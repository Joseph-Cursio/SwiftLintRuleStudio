//
//  ImpactSimulator.swift
//  SwiftLintRuleStudio
//
//  Service for simulating rule violations without actually enabling rules
//

import Foundation
import SwiftLintCLISeam

/// Service for simulating the impact of enabling rules
public class ImpactSimulator: ImpactSimulatorProtocol {

    // MARK: - Properties

    private let swiftLintCLI: SwiftLintCLIProtocol
    private let workspaceBuilder: any SimulationWorkspaceBuilding
    private let now: DateProvider
    private let makeID: IDProvider

    // MARK: - Initialization

    /// Creates a simulator backed by the given SwiftLint CLI and file manager.
    ///
    /// `now` and `makeID` default to the system clock and random identifiers, so no existing
    /// call site changes. A test supplies its own to make the simulator a function of its
    /// inputs: every duration this type reports is a gap between two clock reads, and every
    /// violation it builds carries an identifier, so both have to be chosen for two runs over
    /// the same workspace to produce equal results.
    public convenience init(
        swiftLintCLI: SwiftLintCLIProtocol,
        fileManager: FileManager = .default,
        now: DateProvider = .system,
        makeID: IDProvider = .random
    ) {
        self.init(
            swiftLintCLI: swiftLintCLI,
            workspaceBuilder: SimulationWorkspaceBuilder(fileManager: fileManager),
            now: now,
            makeID: makeID
        )
    }

    /// The seam initializer. Internal rather than public because
    /// `SimulationWorkspaceBuilding` returns a `SimulationWorkspace`, which is internal — making
    /// the parameter public would mean exporting a shadow-workspace type that no consumer of this
    /// package has any use for. The public initializer above is unchanged, so no call site moves.
    init(
        swiftLintCLI: SwiftLintCLIProtocol,
        workspaceBuilder: any SimulationWorkspaceBuilding,
        now: DateProvider = .system,
        makeID: IDProvider = .random
    ) {
        self.swiftLintCLI = swiftLintCLI
        self.workspaceBuilder = workspaceBuilder
        self.now = now
        self.makeID = makeID
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
        if let result = Self.unmeasurableResult(
            for: ruleId,
            isAnalyzer: options.isAnalyzer,
            isSourceKitUnavailable: options.isSourceKitUnavailable
        ) {
            return result
        }

        // Mirror the workspace once, enable the rule as Enable will, lint the mirror.
        let shadow = try await workspaceBuilder.makeWorkspace(for: workspace, baseConfigPath: baseConfigPath)
        defer { release(shadow) }

        return try await measureRule(
            ruleId,
            on: shadow,
            isOptIn: options.isOptIn,
            parameterOverrides: options.parameterOverrides
        )
    }

    /// The result for a rule linting cannot measure here, or nil when it can.
    ///
    /// Linting such a rule would report 0 whatever the code holds, and 0 is what "safe to
    /// enable" means, so it is reported as unmeasurable without spending a lint of the whole
    /// workspace on it. Both reasons (see ``UnmeasurableReason``) are decided here, so the
    /// single-rule sheet and the audit can't disagree. The analyzer reason is checked first:
    /// it holds in every edition, SourceKit's only in the sandboxed one.
    private static func unmeasurableResult(
        for ruleId: String,
        isAnalyzer: Bool,
        isSourceKitUnavailable: Bool
    ) -> RuleImpactResult? {
        if isAnalyzer {
            return .unmeasurable(ruleId: ruleId, reason: .analyzerRule)
        }
        if isSourceKitUnavailable {
            return .unmeasurable(ruleId: ruleId, reason: .sourceKitUnavailable)
        }
        return nil
    }

    /// Removes `shadow` — at once, unless the simulation was cancelled. A backend may then
    /// still be reading it in a lint it stopped waiting for, and SwiftLint treats a config that
    /// vanishes mid-read as fatal, which in-process is the app; so it goes once that lint is over.
    private func release(_ shadow: SimulationWorkspace) {
        guard Task.isCancelled else {
            shadow.cleanupInBackground()
            return
        }
        let root = shadow.root
        let swiftLintCLI = swiftLintCLI
        Task {
            await swiftLintCLI.waitForAbandonedLints(at: root)
            shadow.cleanupInBackground()
        }
    }

    /// Enables `ruleId` in the mirror's root config, as Enable will, lints it, and tallies the
    /// violations attributable to that rule. Shared by single and batch paths so
    /// a batch audit can reuse one mirror across many rules. Never handed a rule linting
    /// can't measure — see `unmeasurableResult(for:isAnalyzer:isSourceKitUnavailable:)`.
    private func measureRule(
        _ ruleId: String,
        on shadow: SimulationWorkspace,
        isOptIn: Bool,
        parameterOverrides: [String: AnyCodable]?
    ) async throws -> RuleImpactResult {
        let startTime = now()

        try shadow.applyRule(
            ruleId,
            isOptIn: isOptIn,
            isAnalyzer: false,
            parameterOverrides: parameterOverrides
        )

        // `.effective` mode with `cwd` = the mirror root: SwiftLint discovers the
        // mirror's (rule-enabled) root and nested configs itself. `configPath` is
        // deliberately nil — passing `--config` would disable nested resolution.
        // The rule runs alone wherever that counts the same, sparing a lint of every rule.
        let lintData = try await swiftLintCLI.executeSimulationLintCommand(
            workspacePath: shadow.root,
            onlyRule: shadow.onlyRule(for: ruleId)
        )

        // Paths come back rooted at the mirror; stripping that prefix yields the
        // same workspace-relative paths the real workspace would produce. A file
        // reached through a link to a folder outside the workspace comes back at its
        // mirror copy's path, and is put back at its real one.
        let decoded = try await LintReportDecoder.decodeOffMainActor(
            lintData,
            workspacePath: shadow.root,
            mapping: shadow.pathMapping,
            ruleIds: shadow.reportedRuleIds(for: ruleId)
        )
        let ruleViolations = decoded.map(makeViolation)
        let affectedFiles = Set(ruleViolations.map(\.filePath))

        return RuleImpactResult(
            ruleId: ruleId,
            violationCount: ruleViolations.count,
            violations: ruleViolations,
            affectedFiles: affectedFiles,
            simulationDuration: now().timeIntervalSince(startTime)
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
        let startTime = now()
        var results: [RuleImpactResult] = []

        // Mirror the workspace once; each rule only rewrites the mirror's configs. A workspace
        // that can't be mirrored fails each rule that needed a lint, with the reason, rather
        // than the whole batch, so the rules linting can't measure are still told apart.
        let shadow: SimulationWorkspace?
        var mirrorFailure: String?
        do {
            shadow = try await workspaceBuilder.makeWorkspace(for: workspace, baseConfigPath: baseConfigPath)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            shadow = nil
            mirrorFailure = error.localizedDescription
        }
        defer {
            if let shadow { release(shadow) }
        }

        for (index, ruleId) in ruleIds.enumerated() {
            // An audit that was cancelled — its workspace closed, say — stops here rather
            // than linting every remaining rule for a result nobody will see.
            try Task.checkCancellation()

            // Counted from 1: the rule now being simulated, so the last reads "N of N".
            progressHandler?(index + 1, ruleIds.count, ruleId)

            if let result = Self.unmeasurableResult(
                for: ruleId,
                isAnalyzer: classification.analyzerRuleIds.contains(ruleId),
                isSourceKitUnavailable: classification.sourceKitUnavailableRuleIds.contains(ruleId)
            ) {
                results.append(result)
                continue
            }

            guard let shadow else {
                results.append(.failed(ruleId: ruleId, reason: mirrorFailure))
                continue
            }

            do {
                let result = try await measureRule(
                    ruleId,
                    on: shadow,
                    isOptIn: classification.optInRuleIds.contains(ruleId),
                    parameterOverrides: nil
                )
                results.append(result)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // One rule failing must not sink the batch, but it must not pass for a clean
                // run either: record the failure and why, so the audit can show it as one.
                results.append(.failed(ruleId: ruleId, reason: error.localizedDescription))
            }
        }

        let duration = now().timeIntervalSince(startTime)

        return BatchSimulationResult(
            results: results,
            totalDuration: duration,
            completedAt: now()
        )
    }

    /// Find all disabled rules with zero violations (safe to enable)
    /// - Parameters:
    ///   - workspace: The workspace to analyze
    ///   - baseConfigPath: Path to the base SwiftLint configuration
    ///   - disabledRuleIds: Array of disabled rule identifiers to check
    ///   - progressHandler: Optional callback for progress updates
    /// - Returns: Array of rule IDs that are safe to enable (measured, with zero violations)
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

        // `safeRules` holds measured, clean rules only. A failed or unmeasurable simulation
        // has no count to call clean.
        return batchResult.safeRules.map(\.ruleId)
    }

    // MARK: - Helper Methods

    /// Parse violations from SwiftLint JSON output
    ///
    /// - Parameter mapping: Puts a path in a mirrored outside folder back at the real one.
    func parseViolations(
        from data: Data,
        workspacePath: URL,
        mapping: MirrorPathMapping? = nil
    ) throws -> [Violation] {
        try LintReportDecoder.decode(data, workspacePath: workspacePath, mapping: mapping, ruleIds: nil)
            .map(makeViolation)
    }

    private func makeViolation(_ decoded: DecodedViolation) -> Violation {
        Violation(
            ruleID: decoded.ruleID,
            filePath: decoded.filePath,
            line: decoded.line,
            severity: Severity(rawValue: decoded.severity) ?? .warning,
            message: decoded.message,
            id: makeID(),
            column: decoded.column,
            detectedAt: now()
        )
    }
}
