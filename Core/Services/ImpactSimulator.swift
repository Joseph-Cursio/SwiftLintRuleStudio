//
//  ImpactSimulator.swift
//  SwiftLintRuleStudio
//
//  Service for simulating rule violations without actually enabling rules
//

import Foundation

/// Result of simulating a rule's impact
struct RuleImpactResult {
    let ruleId: String
    let violationCount: Int
    let violations: [Violation]
    let affectedFiles: Set<String>
    let simulationDuration: TimeInterval

    nonisolated var hasViolations: Bool {
        violationCount > 0
    }

    nonisolated var isSafe: Bool {
        violationCount == 0
    }
}

/// Result of batch simulation
struct BatchSimulationResult {
    let results: [RuleImpactResult]
    let totalDuration: TimeInterval
    let completedAt: Date

    nonisolated var safeRules: [RuleImpactResult] {
        results.filter { $0.isSafe }
    }

    nonisolated var rulesWithViolations: [RuleImpactResult] {
        results.filter { $0.hasViolations }
    }
}

/// Service for simulating the impact of enabling rules
@MainActor
class ImpactSimulator {
    
    // MARK: - Properties
    
    private let swiftLintCLI: SwiftLintCLIProtocol
    private let fileManager: FileManager
    
    // MARK: - Initialization
    
    init(swiftLintCLI: SwiftLintCLIProtocol, fileManager: FileManager = .default) {
        self.swiftLintCLI = swiftLintCLI
        self.fileManager = fileManager
    }
    
    // MARK: - Single Rule Simulation
    
    /// Simulate the impact of enabling a single rule
    /// - Parameters:
    ///   - ruleId: The rule identifier to simulate
    ///   - workspace: The workspace to analyze
    ///   - baseConfigPath: Path to the base SwiftLint configuration
    /// - Returns: Impact result with violation count and details
    func simulateRule(
        ruleId: String,
        workspace: Workspace,
        baseConfigPath: URL?,
        isOptIn: Bool = false
    ) async throws -> RuleImpactResult {
        let startTime = Date()
        
        // Create temporary config with rule enabled
        let tempConfigPath = try createTemporaryConfig(
            ruleId: ruleId,
            enabled: true,
            baseConfigPath: baseConfigPath,
            workspace: workspace,
            isOptIn: isOptIn
        )
        
        defer {
            // Clean up temporary config
            try? fileManager.removeItem(at: tempConfigPath)
        }
        
        // Run SwiftLint with temporary config
        let lintData = try await swiftLintCLI.executeLintCommand(
            configPath: tempConfigPath,
            workspacePath: workspace.path
        )
        
        // Parse violations
        let allViolations = try parseViolations(from: lintData, workspacePath: workspace.path)
        
        // Filter to only violations for this specific rule
        let ruleViolations = allViolations.filter { $0.ruleID == ruleId }
        
        // Extract affected files
        let affectedFiles = Set(ruleViolations.map { $0.filePath })
        
        let duration = Date().timeIntervalSince(startTime)
        
        return RuleImpactResult(
            ruleId: ruleId,
            violationCount: ruleViolations.count,
            violations: ruleViolations,
            affectedFiles: affectedFiles,
            simulationDuration: duration
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
    func simulateRules(
        ruleIds: [String],
        workspace: Workspace,
        baseConfigPath: URL?,
        optInRuleIds: Set<String> = [],
        progressHandler: ((Int, Int, String) -> Void)? = nil
    ) async throws -> BatchSimulationResult {
        let startTime = Date()
        var results: [RuleImpactResult] = []
        
        for (index, ruleId) in ruleIds.enumerated() {
            // Report progress
            progressHandler?(index, ruleIds.count, ruleId)
            
            do {
                let result = try await simulateRule(
                    ruleId: ruleId,
                    workspace: workspace,
                    baseConfigPath: baseConfigPath,
                    isOptIn: optInRuleIds.contains(ruleId)
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
        
        let duration = Date().timeIntervalSince(startTime)
        
        return BatchSimulationResult(
            results: results,
            totalDuration: duration,
            completedAt: Date()
        )
    }
    
    /// Find all disabled rules with zero violations (safe to enable)
    /// - Parameters:
    ///   - workspace: The workspace to analyze
    ///   - baseConfigPath: Path to the base SwiftLint configuration
    ///   - disabledRuleIds: Array of disabled rule identifiers to check
    ///   - progressHandler: Optional callback for progress updates
    /// - Returns: Array of rule IDs that are safe to enable (zero violations)
    func findSafeRules(
        workspace: Workspace,
        baseConfigPath: URL?,
        disabledRuleIds: [String],
        optInRuleIds: Set<String> = [],
        progressHandler: ((Int, Int, String) -> Void)? = nil
    ) async throws -> [String] {
        let batchResult = try await simulateRules(
            ruleIds: disabledRuleIds,
            workspace: workspace,
            baseConfigPath: baseConfigPath,
            optInRuleIds: optInRuleIds,
            progressHandler: progressHandler
        )
        
        // Filter to rules with zero violations (and no errors)
        return batchResult.safeRules
            .filter { $0.violationCount >= 0 } // Exclude error cases
            .map { $0.ruleId }
    }
    
    // MARK: - Helper Methods
    
    /// Create a temporary SwiftLint configuration with a specific rule enabled
    private func createTemporaryConfig(
        ruleId: String,
        enabled: Bool,
        baseConfigPath: URL?,
        workspace: Workspace,
        isOptIn: Bool
    ) throws -> URL {
        // Create temporary directory for config
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("SwiftLintRuleStudio", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let tempConfigPath = tempDir.appendingPathComponent(".swiftlint.yml")
        
        // Load base config if it exists
        let configPathToUse = baseConfigPath
            ?? workspace.configPath
            ?? workspace.path.appendingPathComponent(".swiftlint.yml")
        let yamlEngine = YAMLConfigurationEngine(configPath: configPathToUse)
        
        if fileManager.fileExists(atPath: configPathToUse.path) {
            try yamlEngine.load()
        }
        
        var config = yamlEngine.getConfig()

        // Ensure default exclusions are present so simulations
        // don't count violations in build artifacts or dependencies.
        // Because the temp config lives outside the workspace, SwiftLint
        // resolves relative excluded paths against the temp directory
        // (not the workspace). Convert them to absolute paths so they
        // resolve correctly regardless of where the config file sits.
        let merged = DefaultExclusions.mergedWith(existing: config.excluded)
        config.excluded = merged.map { entry in
            if entry.hasPrefix("/") {
                return entry  // already absolute
            }
            return workspace.path.appendingPathComponent(entry).path
        }

        // Enable the specific rule
        if config.rules[ruleId] == nil {
            // Rule not in config, add it as enabled
            config.rules[ruleId] = RuleConfiguration(enabled: true)
        } else if var ruleConfig = config.rules[ruleId] {
            // Rule exists, update it to enabled
            ruleConfig.enabled = true
            config.rules[ruleId] = ruleConfig
        }

        // Ensure opt-in rules are enabled via opt_in_rules
        if isOptIn {
            var optInRules = config.optInRules ?? []
            if !optInRules.contains(ruleId) {
                optInRules.append(ruleId)
                config.optInRules = optInRules
            }
        }

        // Ensure only_rules includes this rule if configured
        if var onlyRules = config.onlyRules {
            if !onlyRules.contains(ruleId) {
                onlyRules.append(ruleId)
                config.onlyRules = onlyRules
            }
        }
        
        // Remove from disabled rules list if present
        if var disabledRules = config.disabledRules {
            disabledRules.removeAll { $0 == ruleId }
            config.disabledRules = disabledRules.isEmpty ? nil : disabledRules
        }
        
        // Save to temporary location
        let tempEngine = YAMLConfigurationEngine(configPath: tempConfigPath)
        tempEngine.updateConfig(config)
        try tempEngine.save(config: config, createBackup: false)
        
        return tempConfigPath
    }
    
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
                id: UUID(),
                ruleID: ruleId,
                filePath: relativePath,
                line: line,
                column: column,
                severity: severity,
                message: reason,
                detectedAt: Date()
            )
            
            violations.append(violation)
        }
        
        return violations
    }
}
