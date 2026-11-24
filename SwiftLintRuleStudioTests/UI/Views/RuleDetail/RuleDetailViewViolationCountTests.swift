//
//  RuleDetailViewViolationCountTests.swift
//  SwiftLintRuleStudioTests
//
//  The rule detail view's "Current Violations" count: loaded from violation storage when the
//  view appears, and reloaded when an analysis finishes.
//

import Combine
import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import SwiftUI
import Testing
import ViewInspector

/// Violation storage whose count query fails, as a locked or corrupt database would.
private final class FailingViolationStorage: ViolationStorageProtocol, @unchecked Sendable {
    struct ReadError: LocalizedError {
        var errorDescription: String? { "database is locked" }
    }

    func storeViolations(_: [Violation], for _: UUID) throws { throw ReadError() }
    func fetchViolations(filter _: ViolationFilter, workspaceId _: UUID?) throws -> [Violation] { throw ReadError() }
    func suppressViolations(_: [UUID], reason _: String) throws { throw ReadError() }
    func resolveViolations(_: [UUID]) throws { throw ReadError() }
    func deleteViolations(for _: UUID) throws { throw ReadError() }
    func getViolationCount(filter _: ViolationFilter, workspaceId _: UUID?) throws -> Int { throw ReadError() }
}

/// An analyzer the test drives: sending `true` then `false` is an analysis starting and finishing.
@MainActor
private final class ControllableWorkspaceAnalyzer: WorkspaceAnalyzerProtocol {
    let analyzing = CurrentValueSubject<Bool, Never>(false)
    var isAnalyzing: Bool { analyzing.value }
    var isAnalyzingPublisher: AnyPublisher<Bool, Never> { analyzing.eraseToAnyPublisher() }
    var progressPublisher: AnyPublisher<AnalysisProgress?, Never> { Just(nil).eraseToAnyPublisher() }

    func analyze(workspace _: Workspace, configPath _: URL?) throws -> AnalysisResult {
        AnalysisResult(violations: [], filesAnalyzed: 0, duration: 0, startedAt: .now, completedAt: .now)
    }

    func hasAnalyzed(workspaceID _: UUID) -> Bool { false }
}

@MainActor
struct RuleDetailViewViolationCountTests {
    private static let rule = Rule(
        id: "test_rule",
        name: "Test Rule",
        description: "Test description",
        category: .lint,
        isOptIn: false
    )

    /// Three open violations of `test_rule`, plus ones the count must leave out: a suppressed
    /// one of the same rule and two of another rule.
    private static func storageWithViolations() -> MockViolationStorageForViewModel {
        let storage = MockViolationStorageForViewModel()
        storage.storedViolations = [
            ViolationInspectorViewModelTestHelpers.createTestViolation(line: 1),
            ViolationInspectorViewModelTestHelpers.createTestViolation(line: 2),
            ViolationInspectorViewModelTestHelpers.createTestViolation(line: 3),
            ViolationInspectorViewModelTestHelpers.createTestViolation(line: 4, suppressed: true),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "other_rule", line: 5),
            ViolationInspectorViewModelTestHelpers.createTestViolation(ruleID: "other_rule", line: 6),
        ]
        return storage
    }

    /// Host the rule detail view, loading its count into `count`, so its tasks run. It is hosted
    /// under the calling test's name, which that test's `ViewHosting.expel()` removes.
    private static func host(
        _ count: RuleViolationCount,
        container: DependencyContainer,
        function: String = #function
    ) {
        let view = RuleDetailView(rule: rule, viewModel: RuleDetailViewModel(rule: rule), violationCount: count)
            .environment(\.dependencies, container)
        ViewHosting.expel(function: function)
        ViewHosting.host(view: view, function: function)
    }

    /// Whether `count` reaches `expected` within three seconds.
    private static func wait(for expected: RuleViolationCount.State, in count: RuleViolationCount) async -> Bool {
        await UIAsyncTestHelpers.waitForConditionOnMainActor(timeout: 3.0) { count.state == expected }
    }

    private static func texts(for state: RuleViolationCount.State) throws -> [String] {
        try RuleDetailView(rule: rule)
            .violationsCountView(state: state)
            .inspect()
            .findAll(ViewType.Text.self)
            .map { try $0.string() }
    }

    // MARK: - Loading

    @Test("Counts the rule's unsuppressed stored violations")
    func countsUnsuppressedViolationsOfTheRule() async {
        let count = RuleViolationCount()
        await count.load(ruleID: "test_rule", workspaceID: UUID(), storage: Self.storageWithViolations())
        #expect(count.state == .loaded(3))
    }

    @Test("With no workspace open the count is 0")
    func noWorkspaceCountsZero() async {
        let count = RuleViolationCount()
        await count.load(ruleID: "test_rule", workspaceID: nil, storage: Self.storageWithViolations())
        #expect(count.state == .loaded(0))
    }

    @Test("A failed read says why instead of showing 0")
    func failedReadReportsTheError() async {
        let count = RuleViolationCount()
        await count.load(ruleID: "test_rule", workspaceID: UUID(), storage: FailingViolationStorage())
        #expect(count.state == .failed("Couldn't load violations: database is locked"))
    }

    // MARK: - The section

    @Test("The section shows a loaded count, singular and plural")
    func sectionShowsCount() throws {
        #expect(try Self.texts(for: .loaded(3)) == ["Current Violations", "3", "violations", "in current workspace"])
        #expect(try Self.texts(for: .loaded(1)) == ["Current Violations", "1", "violation", "in current workspace"])
        #expect(try Self.texts(for: .loaded(0)) == ["Current Violations", "0", "violations"])
    }

    @Test("The section shows why the count failed to load, and no number")
    func sectionShowsFailure() throws {
        let texts = try Self.texts(for: .failed("Couldn't load violations: database is locked"))
        #expect(texts == ["Current Violations", "Couldn't load violations: database is locked"])
    }

    // MARK: - When the view loads it

    @Test("The view loads the stored count for its rule when it appears")
    func viewLoadsStoredCount() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        let workspaceManager = WorkspaceManager.createForTesting(testName: #function)
        try workspaceManager.openWorkspace(at: tempDir)
        let container = DependencyContainer.createForTesting(
            violationStorage: Self.storageWithViolations(),
            workspaceManager: workspaceManager
        )
        let count = RuleViolationCount()

        Self.host(count, container: container)
        defer { ViewHosting.expel() }

        #expect(await Self.wait(for: .loaded(3), in: count))
    }

    @Test("With no workspace open the view loads 0")
    func viewWithoutWorkspaceLoadsZero() async {
        let container = DependencyContainer.createForTesting(
            violationStorage: Self.storageWithViolations(),
            workspaceManager: WorkspaceManager.createForTesting(testName: #function)
        )
        let count = RuleViolationCount()

        Self.host(count, container: container)
        defer { ViewHosting.expel() }

        #expect(await Self.wait(for: .loaded(0), in: count))
    }

    @Test("The view reloads the count when an analysis finishes")
    func viewReloadsAfterAnalysis() async throws {
        let tempDir = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(tempDir) }
        let workspaceManager = WorkspaceManager.createForTesting(testName: #function)
        try workspaceManager.openWorkspace(at: tempDir)
        let storage = MockViolationStorageForViewModel()
        storage.storedViolations = [ViolationInspectorViewModelTestHelpers.createTestViolation()]
        let analyzer = ControllableWorkspaceAnalyzer()
        let container = DependencyContainer(
            swiftLintCLI: MockSwiftLintCLIActor(),
            cacheManager: CacheManager.createForTesting(),
            violationStorage: storage,
            workspaceManager: workspaceManager,
            onboardingManager: OnboardingManager.createForTesting(testName: #function),
            workspaceAnalyzer: analyzer,
            userDefaults: IsolatedUserDefaults.create(for: #function)
        )
        let count = RuleViolationCount()

        Self.host(count, container: container)
        defer { ViewHosting.expel() }
        #expect(await Self.wait(for: .loaded(1), in: count))

        // The analysis stores what it found, then finishes.
        storage.storedViolations = Self.storageWithViolations().storedViolations
        analyzer.analyzing.send(true)
        analyzer.analyzing.send(false)

        #expect(await Self.wait(for: .loaded(3), in: count))
    }
}
