//
//  VersionCompatibilityViewModel.swift
//  SwiftLintRuleStudio
//
//  View model for version compatibility checking
//

import Foundation
import Observation
import SwiftLintCLISeam
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

                // NOTE: `loadConfig(at:)` does synchronous file I/O, an existing design
                // constraint of the Core layer's @MainActor isolation. Avoid heavy configs.
                let config = try YAMLConfigurationEngine.loadConfig(at: configPath)

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
            var config = try YAMLConfigurationEngine.loadConfig(at: configPath)
            // The rule configurations and all four rule lists, as the migration assistant does.
            config.renameRule(rule.oldRuleId, to: rule.newRuleId)
            try YAMLConfigurationEngine.save(config, to: configPath)

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
