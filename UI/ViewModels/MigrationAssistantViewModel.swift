//
//  MigrationAssistantViewModel.swift
//  SwiftLintRuleStudio
//
//  View model for the migration assistant
//

import Foundation
import Combine

@MainActor
class MigrationAssistantViewModel: ObservableObject {
    @Published var currentVersion: String?
    @Published var previousVersion: String = ""
    @Published var migrationPlan: MigrationPlan?
    @Published var previewDiff: YAMLConfigurationEngine.ConfigDiff?
    @Published var isDetecting: Bool = false
    @Published var isMigrating: Bool = false
    @Published var error: Error?
    @Published var migrationComplete: Bool = false

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

        isDetecting = true
        error = nil
        migrationPlan = nil
        previewDiff = nil
        migrationComplete = false

        Task {
            do {
                let version = try await swiftLintCLI.getVersion()
                currentVersion = version

                let engine = YAMLConfigurationEngine(configPath: configPath)
                try engine.load()
                let config = engine.getConfig()

                migrationPlan = assistant.detectMigrations(
                    config: config,
                    fromVersion: previousVersion,
                    toVersion: version
                )
            } catch {
                self.error = error
            }
            isDetecting = false
        }
    }

    func previewChanges() {
        guard let configPath = configPath,
              let plan = migrationPlan else { return }

        do {
            let engine = YAMLConfigurationEngine(configPath: configPath)
            try engine.load()
            var config = engine.getConfig()

            assistant.applyMigration(plan, to: &config)
            previewDiff = engine.generateDiff(proposedConfig: config)
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
            let engine = YAMLConfigurationEngine(configPath: configPath)
            try engine.load()
            var config = engine.getConfig()

            assistant.applyMigration(plan, to: &config)
            try engine.save(config: config, createBackup: true)

            migrationComplete = true
        } catch {
            self.error = error
        }
        isMigrating = false
    }
}

// MARK: - Errors

enum MigrationError: LocalizedError {
    case noPreviousVersion

    var errorDescription: String? {
        switch self {
        case .noPreviousVersion:
            return "Please enter the previous SwiftLint version you are migrating from."
        }
    }
}
