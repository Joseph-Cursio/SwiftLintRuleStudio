//
//  MigrationAssistantViewModel.swift
//  SwiftLintRuleStudio
//
//  View model for the migration assistant
//

import Foundation
import Observation
import SwiftLintCLISeam
import SwiftLintRuleStudioCore

enum MigrationError: LocalizedError {
    case noPreviousVersion

    var errorDescription: String? {
        switch self {
        case .noPreviousVersion:
            return "Please enter the previous SwiftLint version you are migrating from."
        }
    }
}

@MainActor
@Observable
class MigrationAssistantViewModel {
    var currentVersion: String?
    var previousVersion: String = ""
    var migrationPlan: MigrationPlan?
    var previewDiff: YAMLConfigurationEngine.ConfigDiff?
    var isDetecting: Bool = false
    var isMigrating: Bool = false
    var error: Error?
    var migrationComplete: Bool = false

    /// The in-flight migration detection, if any. Cancelled and replaced on
    /// re-invocation so a superseded run cannot overwrite the newer one's result.
    @ObservationIgnored private(set) var detectTask: Task<Void, Never>?

    private let assistant: MigrationAssistantProtocol
    private let swiftLintCLI: SwiftLintCLIProtocol
    private let configPath: URL?

    init(
        assistant: MigrationAssistantProtocol,
        swiftLintCLI: SwiftLintCLIProtocol,
        configPath: URL?
    ) {
        self.assistant = assistant
        self.swiftLintCLI = swiftLintCLI
        self.configPath = configPath
    }

    func detectMigrations() {
        guard !previousVersion.isEmpty else {
            error = MigrationError.noPreviousVersion
            return
        }
        guard let configPath = configPath else {
            error = YAMLConfigError.fileNotFound
            return
        }

        detectTask?.cancel()
        isDetecting = true
        error = nil
        migrationPlan = nil
        previewDiff = nil
        migrationComplete = false

        detectTask = Task {
            do {
                let version = try await swiftLintCLI.getVersion()
                // Superseded by a newer detection — leave the newer run's state alone.
                guard !Task.isCancelled else { return }

                let config = try YAMLConfigurationEngine.loadConfig(at: configPath)

                currentVersion = version
                migrationPlan = assistant.detectMigrations(
                    config: config,
                    fromVersion: previousVersion,
                    toVersion: version
                )
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error
            }
            guard !Task.isCancelled else { return }
            isDetecting = false
        }
    }

    func previewChanges() {
        guard let configPath = configPath,
              let plan = migrationPlan else { return }

        do {
            let current = try YAMLConfigurationEngine.loadConfig(at: configPath)
            var config = current

            assistant.applyMigration(plan, to: &config)
            previewDiff = YAMLConfigurationEngine.diff(from: current, to: config)
        } catch {
            self.error = error
        }
    }

    func applyMigration() {
        guard let configPath = configPath,
              let plan = migrationPlan else { return }

        isMigrating = true
        error = nil

        do {
            var config = try YAMLConfigurationEngine.loadConfig(at: configPath)

            assistant.applyMigration(plan, to: &config)
            try YAMLConfigurationEngine.save(config, to: configPath)

            migrationComplete = true
        } catch {
            self.error = error
        }
        isMigrating = false
    }
}
