//
//  DashboardViewModelTests.swift
//  SwiftLintRuleStudioTests
//
//  The Dashboard's counts and health report for a workspace.
//

import Combine
import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

// The protocol's methods are async; this stub has nothing to await.
// swiftlint:disable async_without_await
/// Returns whatever violations it holds, ignoring the filter, so the view model's own
/// open-violation filtering is what the tests exercise.
private final class StubViolationStorage: ViolationStorageProtocol, @unchecked Sendable {
    var violations: [Violation] = []

    func storeViolations(_: [Violation], for _: UUID) async throws {}
    func fetchViolations(filter _: ViolationFilter, workspaceId _: UUID?) async throws -> [Violation] { violations }
    func suppressViolations(_: [UUID], reason _: String) async throws {}
    func resolveViolations(_: [UUID]) async throws {}
    func deleteViolations(for _: UUID) async throws {}
    func getViolationCount(filter _: ViolationFilter, workspaceId _: UUID?) async throws -> Int { violations.count }
}

/// Reports the workspaces in `analyzed` as analyzed this launch; never runs an analysis.
@MainActor
private final class StubWorkspaceAnalyzer: WorkspaceAnalyzerProtocol {
    var analyzed: Set<UUID> = []
    let isAnalyzing = false
    var isAnalyzingPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }

    func analyze(workspace _: Workspace, configPath _: URL?) async throws -> AnalysisResult {
        AnalysisResult(violations: [], filesAnalyzed: 0, duration: 0, startedAt: .now, completedAt: .now)
    }

    func hasAnalyzed(workspaceID: UUID) -> Bool { analyzed.contains(workspaceID) }
}
// swiftlint:enable async_without_await

/// A config engine whose load always fails, as an unreadable `.swiftlint.yml` would.
private final class FailingConfigEngine: YAMLConfigurationEngineProtocol {
    struct LoadError: LocalizedError {
        var errorDescription: String? { "bad YAML" }
    }

    func load() throws { throw LoadError() }

    func getConfig() -> YAMLConfigurationEngine.YAMLConfig { YAMLConfigurationEngine.YAMLConfig() }

    func generateDiff(
        proposedConfig _: YAMLConfigurationEngine.YAMLConfig
    ) -> YAMLConfigurationEngine.ConfigDiff {
        YAMLConfigurationEngine.ConfigDiff(
            addedRules: [], removedRules: [], modifiedRules: [], before: "", after: ""
        )
    }

    func validate(_: YAMLConfigurationEngine.YAMLConfig) throws {}

    func save(config _: YAMLConfigurationEngine.YAMLConfig, createBackup _: Bool) throws {}
}

@MainActor
struct DashboardViewModelTests {
    /// Every rule claims to be enabled: the registry's flags only track whatever config the
    /// Rules browser last synced, so the Dashboard has to ignore them.
    private func rule(_ id: String, optIn: Bool) -> Rule {
        Rule(id: id, name: id, description: id, category: .style, isOptIn: optIn, isEnabled: true)
    }

    private var rules: [Rule] {
        [
            rule("default_on", optIn: false),
            rule("default_off", optIn: false),
            rule("opt_in_on", optIn: true),
            rule("opt_in_off", optIn: true)
        ]
    }

    private func violation(_ severity: Severity, suppressed: Bool = false, resolved: Bool = false) -> Violation {
        Violation(
            ruleID: "default_on",
            filePath: "A.swift",
            line: 1,
            severity: severity,
            message: "message",
            resolvedAt: resolved ? Date.now : nil,
            suppressed: suppressed
        )
    }

    /// A workspace in a fresh temporary folder, optionally with a `.swiftlint.yml`.
    private func makeWorkspace(config: String?) throws -> Workspace {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let config {
            try config.write(to: folder.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        }
        return Workspace(path: folder)
    }

    private func makeViewModel(
        storage: StubViolationStorage = StubViolationStorage(),
        workspaceAnalyzer: StubWorkspaceAnalyzer = StubWorkspaceAnalyzer(),
        engine: ((URL) -> any YAMLConfigurationEngineProtocol)? = nil
    ) -> DashboardViewModel {
        DashboardViewModel(
            analyzer: ConfigurationHealthAnalyzer(),
            violationStorage: storage,
            workspaceAnalyzer: workspaceAnalyzer,
            makeConfigEngine: engine ?? { YAMLConfigurationEngine(configPath: $0) }
        )
    }

    @Test("Rule counts come from the workspace's config, not the registry's flags")
    func testRuleCounts() async throws {
        let viewModel = makeViewModel()
        let workspace = try makeWorkspace(config: "disabled_rules:\n  - default_off\nopt_in_rules:\n  - opt_in_on\n")
        await viewModel.load(rules: rules, workspace: workspace)

        let stats = try #require(viewModel.stats)
        #expect(stats.totalRules == 4)
        #expect(stats.enabledRules == 2)
        #expect(stats.enabledOptInRules == 1)
    }

    @Test("Without a config file, the counts are SwiftLint's defaults")
    func testRuleCountsWithoutConfigFile() async throws {
        let viewModel = makeViewModel()
        await viewModel.load(rules: rules, workspace: try makeWorkspace(config: nil))

        let stats = try #require(viewModel.stats)
        #expect(stats.enabledRules == 2, "both default rules, neither opt-in rule")
        #expect(stats.enabledOptInRules == 0)
    }

    @Test("Errors and warnings count only open violations")
    func testViolationCounts() async throws {
        let storage = StubViolationStorage()
        storage.violations = [
            violation(.error),
            violation(.error),
            violation(.warning),
            violation(.error, suppressed: true),
            violation(.warning, resolved: true)
        ]
        let viewModel = makeViewModel(storage: storage)
        await viewModel.load(rules: rules, workspace: try makeWorkspace(config: nil))

        let stats = try #require(viewModel.stats)
        #expect(stats.errors == 2)
        #expect(stats.warnings == 1)
    }

    @Test("A workspace never analyzed has no error or warning counts, rather than zero")
    func testUnanalyzedWorkspace() async throws {
        let viewModel = makeViewModel()
        await viewModel.load(rules: rules, workspace: try makeWorkspace(config: nil))

        let stats = try #require(viewModel.stats)
        #expect(stats.errors == nil)
        #expect(stats.warnings == nil)
    }

    @Test("A workspace analyzed clean this launch shows zero errors and warnings")
    func testCleanAnalysis() async throws {
        let workspace = try makeWorkspace(config: nil)
        let workspaceAnalyzer = StubWorkspaceAnalyzer()
        workspaceAnalyzer.analyzed = [workspace.id]
        let viewModel = makeViewModel(workspaceAnalyzer: workspaceAnalyzer)
        await viewModel.load(rules: rules, workspace: workspace)

        let stats = try #require(viewModel.stats)
        #expect(stats.errors == 0)
        #expect(stats.warnings == 0)
    }

    @Test("A workspace with a config file gets a health report from it")
    func testReportFromConfigFile() async throws {
        let viewModel = makeViewModel()
        let workspace = try makeWorkspace(config: "opt_in_rules:\n  - opt_in_on\nexcluded:\n  - Pods\n")
        await viewModel.load(rules: rules, workspace: workspace)

        #expect(viewModel.hasConfigFile)
        #expect(viewModel.errorMessage == nil)
        // Excluding Pods is worth 40 points over the bare 50: the report scored the file.
        #expect(viewModel.report?.breakdown.pathConfiguration == 90)
    }

    @Test("Without a config file the report still scores SwiftLint's defaults, and says so")
    func testReportWithoutConfigFile() async throws {
        let viewModel = makeViewModel()
        await viewModel.load(rules: rules, workspace: try makeWorkspace(config: nil))

        #expect(!viewModel.hasConfigFile)
        #expect(viewModel.report != nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("An unreadable config gives no report or enabled counts, and explains why")
    func testUnreadableConfig() async throws {
        let viewModel = makeViewModel { _ in FailingConfigEngine() }
        await viewModel.load(rules: rules, workspace: try makeWorkspace(config: "bad"))

        #expect(viewModel.report == nil)
        let stats = try #require(viewModel.stats)
        #expect(stats.totalRules == 4)
        #expect(stats.enabledRules == nil, "which rules run is unknown")
        #expect(viewModel.errorMessage?.contains("bad YAML") == true)
    }

    @Test("A later load replaces the earlier error")
    func testErrorClearsOnReload() async throws {
        var failing = true
        let viewModel = makeViewModel { url -> any YAMLConfigurationEngineProtocol in
            failing ? FailingConfigEngine() : YAMLConfigurationEngine(configPath: url)
        }
        let workspace = try makeWorkspace(config: "excluded:\n  - Pods\n")
        await viewModel.load(rules: rules, workspace: workspace)
        #expect(viewModel.errorMessage != nil)

        failing = false
        await viewModel.load(rules: rules, workspace: workspace)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.report != nil)
    }
}
