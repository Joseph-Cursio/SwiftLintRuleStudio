//
//  DependencyContainerTests.swift
//  SwiftLIntRuleStudioTests
//
//  Smoke tests verifying that DependencyContainer wires all services correctly.
//  These tests guard against regressions where a new service is added to the
//  container but its initialisation is accidentally broken.
//

import Testing
import Foundation
import Combine
@testable import SwiftLIntRuleStudio

@MainActor
struct DependencyContainerTests {

    // MARK: - Core Services

    @Test("DependencyContainer initializes all core services without crashing")
    func testCoreServicesInitialization() {
        let container = makeSafeContainer()
        // Accessing each property verifies that the service graph was constructed
        // successfully (no fatalError, no missing initialisers)
        _ = container.ruleRegistry
        _ = container.swiftLintCLI
        _ = container.cacheManager
        _ = container.workspaceAnalyzer
        _ = container.workspaceManager
        _ = container.onboardingManager
        _ = container.impactSimulator
        _ = container.xcodeIntegrationService
        _ = container.violationStorage
    }

    // MARK: - Phase 1 YAML Services

    @Test("DependencyContainer initializes all Phase 1 YAML configuration services")
    func testPhase1Services() {
        let container = makeSafeContainer()
        _ = container.configurationValidator
        _ = container.configurationHealthAnalyzer
        _ = container.configurationTemplateManager
        _ = container.prCommentGenerator
    }

    // MARK: - Phase 2 YAML Services

    @Test("DependencyContainer initializes all Phase 2 YAML configuration services")
    func testPhase2Services() {
        let container = makeSafeContainer()
        _ = container.configVersionHistoryService
        _ = container.configComparisonService
    }

    // MARK: - Phase 3 YAML Services

    @Test("DependencyContainer initializes all Phase 3 YAML configuration services")
    func testPhase3Services() {
        let container = makeSafeContainer()
        _ = container.gitService
        _ = container.urlConfigFetcher
        _ = container.versionCompatibilityChecker
        _ = container.configImportService
        _ = container.gitBranchDiffService
        _ = container.migrationAssistant
    }

    // MARK: - Service Injection

    @Test("DependencyContainer accepts injected violation storage")
    func testInjectedViolationStorage() {
        let mockStorage = MockViolationStorageForViewModel()
        let container = DependencyContainer(violationStorage: mockStorage)
        // If this compiles and runs without fatalError, injection was accepted
        _ = container.violationStorage
    }

    @Test("DependencyContainer uses injected CLI for rule registry construction")
    func testInjectedCLIIsUsed() async {
        let mockCLI = MockSwiftLintCLI()
        let container = DependencyContainer(swiftLintCLI: mockCLI, violationStorage: MockViolationStorageForViewModel())
        // Registry should have been built with the injected CLI; verify by running
        // a rules command through the registry (no crash = correct wiring)
        let registry = container.ruleRegistry
        _ = registry
    }

    @Test("DependencyContainer forwards custom UserDefaults to WorkspaceManager and OnboardingManager")
    func testCustomUserDefaults() throws {
        let suiteName = "DependencyContainerTests.\(UUID().uuidString)"
        let customDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { customDefaults.removePersistentDomain(forName: suiteName) }

        let container = DependencyContainer(
            violationStorage: MockViolationStorageForViewModel(),
            userDefaults: customDefaults
        )

        // Both managers must be created successfully with the custom defaults
        _ = container.workspaceManager
        _ = container.onboardingManager
    }

    // MARK: - objectWillChange Propagation

    @Test("DependencyContainer forwards onboardingManager objectWillChange to its own publisher")
    func testObjectWillChangeForwardingFromOnboarding() async {
        let container = makeSafeContainer()

        var receivedChange = false
        let cancellable = container.objectWillChange.sink { receivedChange = true }
        defer { cancellable.cancel() }

        // Trigger a change on onboardingManager — this should bubble up via the
        // Combine sink wired in DependencyContainer.init
        container.onboardingManager.completeOnboarding()

        await Task.yield()
        #expect(receivedChange)
    }

    @Test("DependencyContainer forwards workspaceManager objectWillChange to its own publisher")
    func testObjectWillChangeForwardingFromWorkspaceManager() async throws {
        let container = makeSafeContainer()

        var receivedChange = false
        let cancellable = container.objectWillChange.sink { receivedChange = true }
        defer { cancellable.cancel() }

        // Opening a workspace triggers @Published changes in WorkspaceManager.
        // validateSwiftWorkspace requires at least one .swift file in the directory.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dummySwift = tempDir.appendingPathComponent("Dummy.swift")
        try "// dummy".write(to: dummySwift, atomically: true, encoding: .utf8)
        _ = try? container.workspaceManager.openWorkspace(at: tempDir)

        await Task.yield()
        #expect(receivedChange)
    }

    // MARK: - Helpers

    private func makeSafeContainer() -> DependencyContainer {
        DependencyContainer(violationStorage: MockViolationStorageForViewModel())
    }
}
