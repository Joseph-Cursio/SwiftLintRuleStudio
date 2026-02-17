//
//  VersionCompatibilityViewModel.swift
//  SwiftLintRuleStudio
//
//  View model for version compatibility checking
//

import Foundation
import Combine

@MainActor
class VersionCompatibilityViewModel: ObservableObject {
    @Published var report: CompatibilityReport?
    @Published var isChecking: Bool = false
    @Published var error: Error?
    @Published var currentVersion: String?

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

        isChecking = true
        error = nil
        report = nil

        Task {
            do {
                let version = try await swiftLintCLI.getVersion()
                currentVersion = version

                let engine = YAMLConfigurationEngine(configPath: configPath)
                try engine.load()
                let config = engine.getConfig()

                report = checker.checkCompatibility(config: config, swiftLintVersion: version)
            } catch {
                self.error = error
            }
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
