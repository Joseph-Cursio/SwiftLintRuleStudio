//
//  VersionCompatibilityViewModel.swift
//  SwiftLintRuleStudio
//
//  View model for version compatibility checking
//

import Foundation
import Observation
import SwiftLintRuleStudioCore

@MainActor
@Observable
class VersionCompatibilityViewModel {
    var report: CompatibilityReport?
    var isChecking: Bool = false
    var error: Error?
    var currentVersion: String?

    /// The in-flight compatibility check, if any. Cancelled and replaced on
    /// re-invocation so a superseded run cannot overwrite the newer one's result.
    @ObservationIgnored private(set) var checkTask: Task<Void, Never>?

    private let checker: VersionCompatibilityCheckerProtocol
    private let swiftLintCLI: SwiftLintCLIProtocol
    private let configPath: URL?

    init(
        checker: VersionCompatibilityCheckerProtocol,
        swiftLintCLI: SwiftLintCLIProtocol,
        configPath: URL?
    ) {
        self.checker = checker
        self.swiftLintCLI = swiftLintCLI
        self.configPath = configPath
    }

    func checkCompatibility() {
        guard let configPath = configPath else {
            error = YAMLConfigError.fileNotFound
            return
        }

        checkTask?.cancel()
        isChecking = true
        error = nil
        report = nil

        checkTask = Task {
            do {
                let version = try await swiftLintCLI.getVersion()
                // Superseded by a newer check — leave the newer run's state alone.
                guard !Task.isCancelled else { return }

                // NOTE: YAMLConfigurationEngine is @MainActor so we must use it here.
                // engine.load() does synchronous file I/O but that is an existing design
                // constraint of YAMLConfigurationEngine. Avoid heavy configs.
                let engine = YAMLConfigurationEngine(configPath: configPath)
                try engine.load()
                let config = engine.getConfig()

                currentVersion = version
                report = checker.checkCompatibility(config: config, swiftLintVersion: version)
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error
            }
            guard !Task.isCancelled else { return }
            isChecking = false
        }
    }

    func applyRenaming(_ rule: RenamedRuleInfo) {
        guard let configPath = configPath else { return }

        do {
            let engine = YAMLConfigurationEngine(configPath: configPath)
            try engine.load()
            var config = engine.getConfig()

            // Move rule config from old to new
            if let ruleConfig = config.rules[rule.oldRuleId] {
                config.rules.removeValue(forKey: rule.oldRuleId)
                config.rules[rule.newRuleId] = ruleConfig
            }

            // Update disabled_rules
            if var disabled = config.disabledRules {
                if let idx = disabled.firstIndex(of: rule.oldRuleId) {
                    disabled[idx] = rule.newRuleId
                    config.disabledRules = disabled
                }
            }

            // Update opt_in_rules
            if var optIn = config.optInRules {
                if let idx = optIn.firstIndex(of: rule.oldRuleId) {
                    optIn[idx] = rule.newRuleId
                    config.optInRules = optIn
                }
            }

            try engine.save(config: config, createBackup: true)

            // Re-run check
            checkCompatibility()
        } catch {
            self.error = error
        }
    }

    func applyAllFixes() {
        guard let report = report else { return }
        for renamed in report.renamedRules {
            applyRenaming(renamed)
        }
    }
}
