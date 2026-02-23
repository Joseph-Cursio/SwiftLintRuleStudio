//
//  VersionCompatibilityViewModelTests.swift
//  SwiftLIntRuleStudioTests
//
//  Tests for VersionCompatibilityViewModel state management and service delegation
//

import Testing
import Foundation
@testable import SwiftLIntRuleStudio

@MainActor
struct VersionCompatibilityViewModelTests {

    // MARK: - Helpers

    private func makeTempConfigURL(yaml: String = "disabled_rules: []\n") throws -> (configPath: URL, tempDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let configPath = tempDir.appendingPathComponent(".swiftlint.yml")
        try yaml.write(to: configPath, atomically: true, encoding: .utf8)
        return (configPath, tempDir)
    }

    private func makeReport(
        version: String = "0.57.0",
        renamed: [RenamedRuleInfo] = []
    ) -> CompatibilityReport {
        CompatibilityReport(
            swiftLintVersion: version,
            deprecatedRules: [],
            removedRules: [],
            renamedRules: renamed,
            availableNewRules: []
        )
    }

    // MARK: - Initial State

    @Test("Initial state has nil report, not checking, no error, no current version")
    func testInitialState() {
        let vm = VersionCompatibilityViewModel(
            checker: SpyCompatibilityChecker(),
            swiftLintCLI: SpyCompatibilityCLI(),
            configPath: nil
        )

        #expect(vm.report == nil)
        #expect(!vm.isChecking)
        #expect(vm.error == nil)
        #expect(vm.currentVersion == nil)
    }

    // MARK: - checkCompatibility() guard path

    @Test("checkCompatibility with nil configPath sets YAMLConfigError synchronously")
    func testCheckCompatibilityNilConfigPathSetsError() {
        let checker = SpyCompatibilityChecker()
        let vm = VersionCompatibilityViewModel(
            checker: checker,
            swiftLintCLI: SpyCompatibilityCLI(),
            configPath: nil
        )

        vm.checkCompatibility()

        #expect(vm.error is YAMLConfigError)
        #expect(checker.checkCallCount == 0)
    }

    // MARK: - checkCompatibility() async Task path

    @Test("checkCompatibility stores error and clears isChecking when CLI throws")
    func testCheckCompatibilityCLIErrorSetsError() async throws {
        let cli = SpyCompatibilityCLI(shouldThrow: true)
        let vm = VersionCompatibilityViewModel(
            checker: SpyCompatibilityChecker(),
            swiftLintCLI: cli,
            configPath: URL(fileURLWithPath: "/tmp/.swiftlint.yml")
        )

        vm.checkCompatibility()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(vm.error != nil)
        #expect(!vm.isChecking)
        #expect(vm.report == nil)
    }

    @Test("checkCompatibility populates report from checker on success")
    func testCheckCompatibilityPopulatesReport() async throws {
        let (configPath, tempDir) = try makeTempConfigURL()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let expectedReport = makeReport(version: "0.57.0")
        let checker = SpyCompatibilityChecker(reportToReturn: expectedReport)
        let cli = SpyCompatibilityCLI(versionToReturn: "0.57.0")
        let vm = VersionCompatibilityViewModel(
            checker: checker,
            swiftLintCLI: cli,
            configPath: configPath
        )

        vm.checkCompatibility()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(checker.checkCallCount == 1)
        #expect(vm.report?.swiftLintVersion == "0.57.0")
        #expect(vm.error == nil)
    }

    @Test("checkCompatibility sets currentVersion from CLI response")
    func testCheckCompatibilitySetsCurrentVersion() async throws {
        let (configPath, tempDir) = try makeTempConfigURL()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cli = SpyCompatibilityCLI(versionToReturn: "0.57.0")
        let vm = VersionCompatibilityViewModel(
            checker: SpyCompatibilityChecker(),
            swiftLintCLI: cli,
            configPath: configPath
        )

        vm.checkCompatibility()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(vm.currentVersion == "0.57.0")
    }

    @Test("checkCompatibility clears isChecking after task completes")
    func testCheckCompatibilityClearsIsChecking() async throws {
        let (configPath, tempDir) = try makeTempConfigURL()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = VersionCompatibilityViewModel(
            checker: SpyCompatibilityChecker(),
            swiftLintCLI: SpyCompatibilityCLI(),
            configPath: configPath
        )

        vm.checkCompatibility()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(!vm.isChecking)
    }

    @Test("checkCompatibility passes parsed config to checker")
    func testCheckCompatibilityPassesConfigToChecker() async throws {
        let (configPath, tempDir) = try makeTempConfigURL(yaml: "disabled_rules:\n  - force_cast\n")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let checker = SpyCompatibilityChecker()
        let vm = VersionCompatibilityViewModel(
            checker: checker,
            swiftLintCLI: SpyCompatibilityCLI(),
            configPath: configPath
        )

        vm.checkCompatibility()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(checker.lastCheckedVersion == "0.57.0")
    }

    // MARK: - applyRenaming()

    @Test("applyRenaming with nil configPath does nothing")
    func testApplyRenamingNilConfigPathDoesNothing() {
        let vm = VersionCompatibilityViewModel(
            checker: SpyCompatibilityChecker(),
            swiftLintCLI: SpyCompatibilityCLI(),
            configPath: nil
        )

        let rule = RenamedRuleInfo(id: "test", oldRuleId: "old_rule", newRuleId: "new_rule")
        vm.applyRenaming(rule)

        #expect(vm.error == nil)
    }

    @Test("applyRenaming with valid config file updates rule names and does not produce error")
    func testApplyRenamingSucceedsWithValidFile() throws {
        let yaml = "disabled_rules:\n  - old_rule\nopt_in_rules:\n  - keep_rule\n"
        let (configPath, tempDir) = try makeTempConfigURL(yaml: yaml)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = VersionCompatibilityViewModel(
            checker: SpyCompatibilityChecker(),
            swiftLintCLI: SpyCompatibilityCLI(),
            configPath: configPath
        )

        let rule = RenamedRuleInfo(id: "test", oldRuleId: "old_rule", newRuleId: "new_rule")
        vm.applyRenaming(rule)

        #expect(vm.error == nil)
    }

    @Test("applyRenaming stores error when config file does not exist")
    func testApplyRenamingErrorOnMissingFile() {
        let vm = VersionCompatibilityViewModel(
            checker: SpyCompatibilityChecker(),
            swiftLintCLI: SpyCompatibilityCLI(),
            configPath: URL(fileURLWithPath: "/nonexistent/path/.swiftlint.yml")
        )

        let rule = RenamedRuleInfo(id: "test", oldRuleId: "old_rule", newRuleId: "new_rule")
        vm.applyRenaming(rule)

        #expect(vm.error != nil)
    }

    // MARK: - applyAllFixes()

    @Test("applyAllFixes with nil report does nothing")
    func testApplyAllFixesNilReportDoesNothing() {
        let vm = VersionCompatibilityViewModel(
            checker: SpyCompatibilityChecker(),
            swiftLintCLI: SpyCompatibilityCLI(),
            configPath: nil
        )

        vm.applyAllFixes()

        #expect(vm.error == nil)
    }
}

// MARK: - Spies

private final class SpyCompatibilityChecker: VersionCompatibilityCheckerProtocol, @unchecked Sendable {
    private let reportToReturn: CompatibilityReport

    var checkCallCount = 0
    var lastCheckedVersion: String?

    init(reportToReturn: CompatibilityReport = CompatibilityReport(
        swiftLintVersion: "0.57.0",
        deprecatedRules: [],
        removedRules: [],
        renamedRules: [],
        availableNewRules: []
    )) {
        self.reportToReturn = reportToReturn
    }

    func checkCompatibility(
        config: YAMLConfigurationEngine.YAMLConfig,
        swiftLintVersion: String
    ) -> CompatibilityReport {
        checkCallCount += 1
        lastCheckedVersion = swiftLintVersion
        return reportToReturn
    }
}

private final class SpyCompatibilityCLI: SwiftLintCLIProtocol, @unchecked Sendable {
    private let versionToReturn: String
    private let shouldThrow: Bool

    init(versionToReturn: String = "0.57.0", shouldThrow: Bool = false) {
        self.versionToReturn = versionToReturn
        self.shouldThrow = shouldThrow
    }

    func getVersion() throws -> String {
        if shouldThrow {
            throw NSError(domain: "SpyCLI", code: 1, userInfo: [NSLocalizedDescriptionKey: "CLI unavailable"])
        }
        return versionToReturn
    }

    func detectSwiftLintPath() throws -> URL { URL(fileURLWithPath: "/usr/bin/swiftlint") }
    func executeRulesCommand() throws -> Data { Data() }
    func executeRuleDetailCommand(ruleId: String) throws -> Data { Data() }
    func generateDocsForRule(ruleId: String) throws -> String { "" }
    func executeLintCommand(configPath: URL?, workspacePath: URL) throws -> Data { Data() }
}
