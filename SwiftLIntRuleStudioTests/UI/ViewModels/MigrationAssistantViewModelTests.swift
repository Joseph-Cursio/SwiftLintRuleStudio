//
//  MigrationAssistantViewModelTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for MigrationAssistantViewModel state management and service delegation
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

@MainActor
struct MigrationAssistantViewModelTests {

    // MARK: - Helpers

    private func makeTempConfigURL(yaml: String = "disabled_rules: []\n") throws -> (configPath: URL, tempDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        try yaml.write(to: configPath, atomically: true, encoding: .utf8)
        return (configPath, tempDir)
    }

    private func makeEmptyPlan() -> MigrationPlan {
        MigrationPlan(fromVersion: "5.0", toVersion: "6.0", steps: [])
    }

    // MARK: - Initial State

    @Test("Initial state has empty previousVersion, nil plan, not detecting/migrating")
    func testInitialState() {
        let spy = SpyMigrationAssistant()
        let vm = MigrationAssistantViewModel(
            assistant: spy,
            swiftLintCLI: SpyMigrationCLI(),
            configPath: nil
        )

        #expect(vm.previousVersion == "")
        #expect(vm.currentVersion == nil)
        #expect(vm.migrationPlan == nil)
        #expect(vm.previewDiff == nil)
        #expect(!vm.isDetecting)
        #expect(!vm.isMigrating)
        #expect(vm.error == nil)
        #expect(!vm.migrationComplete)
    }

    // MARK: - detectMigrations() guard paths

    @Test("detectMigrations with empty previousVersion sets MigrationError synchronously without spawning Task")
    func testDetectMigrationsEmptyPreviousVersionSetsError() {
        let spy = SpyMigrationAssistant()
        let vm = MigrationAssistantViewModel(
            assistant: spy,
            swiftLintCLI: SpyMigrationCLI(),
            configPath: URL(fileURLWithPath: "/tmp/.swiftlint.yml")
        )
        vm.previousVersion = ""

        vm.detectMigrations()

        #expect(vm.error is MigrationError)
        #expect(spy.detectCallCount == 0)
    }

    @Test("detectMigrations with nil configPath sets YAMLConfigError synchronously without spawning Task")
    func testDetectMigrationsNilConfigPathSetsError() {
        let spy = SpyMigrationAssistant()
        let vm = MigrationAssistantViewModel(
            assistant: spy,
            swiftLintCLI: SpyMigrationCLI(),
            configPath: nil
        )
        vm.previousVersion = "5.0"

        vm.detectMigrations()

        #expect(vm.error is YAMLConfigError)
        #expect(spy.detectCallCount == 0)
    }

    // MARK: - detectMigrations() async Task path

    @Test("detectMigrations stores error and clears isDetecting when CLI throws")
    func testDetectMigrationsCLIErrorSetsError() async throws {
        let spy = SpyMigrationAssistant()
        let cli = SpyMigrationCLI(shouldThrow: true)
        let vm = MigrationAssistantViewModel(
            assistant: spy,
            swiftLintCLI: cli,
            configPath: URL(fileURLWithPath: "/tmp/.swiftlint.yml")
        )
        vm.previousVersion = "5.0"

        vm.detectMigrations()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(vm.error != nil)
        #expect(!vm.isDetecting)
        #expect(spy.detectCallCount == 0)
    }

    @Test("detectMigrations populates migrationPlan from assistant on success")
    func testDetectMigrationsPopulatesMigrationPlan() async throws {
        let (configPath, tempDir) = try makeTempConfigURL()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plan = MigrationPlan(
            fromVersion: "5.0",
            toVersion: "6.0",
            steps: [.renameRule(from: "old_rule", to: "new_rule")]
        )
        let spy = SpyMigrationAssistant(planToReturn: plan)
        let cli = SpyMigrationCLI(versionToReturn: "6.0")
        let vm = MigrationAssistantViewModel(
            assistant: spy,
            swiftLintCLI: cli,
            configPath: configPath
        )
        vm.previousVersion = "5.0"

        vm.detectMigrations()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(spy.detectCallCount == 1)
        #expect(vm.migrationPlan?.steps.count == 1)
        #expect(vm.error == nil)
    }

    @Test("detectMigrations sets currentVersion from CLI response")
    func testDetectMigrationsSetsCurrentVersion() async throws {
        let (configPath, tempDir) = try makeTempConfigURL()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let spy = SpyMigrationAssistant()
        let cli = SpyMigrationCLI(versionToReturn: "0.57.0")
        let vm = MigrationAssistantViewModel(
            assistant: spy,
            swiftLintCLI: cli,
            configPath: configPath
        )
        vm.previousVersion = "5.0"

        vm.detectMigrations()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(vm.currentVersion == "0.57.0")
    }

    @Test("detectMigrations clears isDetecting after task completes")
    func testDetectMigrationsClearsIsDetecting() async throws {
        let (configPath, tempDir) = try makeTempConfigURL()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = MigrationAssistantViewModel(
            assistant: SpyMigrationAssistant(),
            swiftLintCLI: SpyMigrationCLI(),
            configPath: configPath
        )
        vm.previousVersion = "5.0"

        vm.detectMigrations()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(!vm.isDetecting)
    }

    // MARK: - previewChanges()

    @Test("previewChanges with nil migrationPlan does nothing")
    func testPreviewChangesNilPlanDoesNothing() {
        let vm = MigrationAssistantViewModel(
            assistant: SpyMigrationAssistant(),
            swiftLintCLI: SpyMigrationCLI(),
            configPath: URL(fileURLWithPath: "/tmp/.swiftlint.yml")
        )

        vm.previewChanges()

        #expect(vm.previewDiff == nil)
        #expect(vm.error == nil)
    }

    @Test("previewChanges calls assistant.applyMigration and sets previewDiff")
    func testPreviewChangesCallsAssistant() throws {
        let (configPath, tempDir) = try makeTempConfigURL()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let spy = SpyMigrationAssistant()
        let vm = MigrationAssistantViewModel(
            assistant: spy,
            swiftLintCLI: SpyMigrationCLI(),
            configPath: configPath
        )
        vm.migrationPlan = makeEmptyPlan()

        vm.previewChanges()

        #expect(spy.applyCallCount == 1)
        #expect(vm.previewDiff != nil)
        #expect(vm.error == nil)
    }

    // MARK: - applyMigration()

    @Test("applyMigration with nil migrationPlan does nothing")
    func testApplyMigrationNilPlanDoesNothing() {
        let spy = SpyMigrationAssistant()
        let vm = MigrationAssistantViewModel(
            assistant: spy,
            swiftLintCLI: SpyMigrationCLI(),
            configPath: URL(fileURLWithPath: "/tmp/.swiftlint.yml")
        )

        vm.applyMigration()

        #expect(spy.applyCallCount == 0)
        #expect(!vm.migrationComplete)
    }

    @Test("applyMigration calls assistant.applyMigration, saves file, and sets migrationComplete")
    func testApplyMigrationCallsAssistantAndCompletes() throws {
        let (configPath, tempDir) = try makeTempConfigURL()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let spy = SpyMigrationAssistant()
        let vm = MigrationAssistantViewModel(
            assistant: spy,
            swiftLintCLI: SpyMigrationCLI(),
            configPath: configPath
        )
        vm.migrationPlan = makeEmptyPlan()

        vm.applyMigration()

        #expect(spy.applyCallCount == 1)
        #expect(vm.migrationComplete)
        #expect(!vm.isMigrating)
        #expect(vm.error == nil)
    }

    @Test("applyMigration stores error and clears isMigrating when file does not exist")
    func testApplyMigrationErrorOnMissingFile() {
        let spy = SpyMigrationAssistant()
        let vm = MigrationAssistantViewModel(
            assistant: spy,
            swiftLintCLI: SpyMigrationCLI(),
            configPath: URL(fileURLWithPath: "/nonexistent/path/.swiftlint.yml")
        )
        vm.migrationPlan = makeEmptyPlan()

        vm.applyMigration()

        #expect(vm.error != nil)
        #expect(!vm.migrationComplete)
        #expect(!vm.isMigrating)
    }
}

// MARK: - Spies

private final class SpyMigrationAssistant: MigrationAssistantProtocol, @unchecked Sendable {
    private let planToReturn: MigrationPlan

    var detectCallCount = 0
    var applyCallCount = 0

    init(planToReturn: MigrationPlan = MigrationPlan(fromVersion: "5.0", toVersion: "6.0", steps: [])) {
        self.planToReturn = planToReturn
    }

    func detectMigrations(
        config: YAMLConfigurationEngine.YAMLConfig,
        fromVersion: String,
        toVersion: String
    ) -> MigrationPlan {
        detectCallCount += 1
        return planToReturn
    }

    func applyMigration(_ plan: MigrationPlan, to config: inout YAMLConfigurationEngine.YAMLConfig) {
        applyCallCount += 1
    }
}

private final class SpyMigrationCLI: SwiftLintCLIProtocol, @unchecked Sendable {
    private let versionToReturn: String
    private let shouldThrow: Bool

    init(versionToReturn: String = "0.57.0", shouldThrow: Bool = false) {
        self.versionToReturn = versionToReturn
        self.shouldThrow = shouldThrow
    }

    func getVersion() async throws -> String {
        if shouldThrow {
            throw NSError(domain: "SpyCLI", code: 1, userInfo: [NSLocalizedDescriptionKey: "CLI unavailable"])
        }
        return versionToReturn
    }

    func detectSwiftLintPath() async throws -> URL { URL(fileURLWithPath: "/usr/bin/swiftlint") }
    func executeRulesCommand() async throws -> Data { Data() }
    func executeRuleDetailCommand(ruleId: String) async throws -> Data { Data() }
    func generateDocsForRule(ruleId: String) async throws -> String { "" }
    func executeLintCommand(configPath: URL?, workspacePath: URL) async throws -> Data { Data() }
}
