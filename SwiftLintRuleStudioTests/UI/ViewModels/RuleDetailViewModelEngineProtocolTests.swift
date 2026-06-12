//
//  RuleDetailViewModelEngineProtocolTests.swift
//  SwiftLintRuleStudioTests
//
//  Verifies RuleDetailViewModel drives the YAML engine through
//  YAMLConfigurationEngineProtocol, so the save/diff flow can be exercised with an
//  in-memory stub instead of a real engine writing to disk.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

/// In-memory `YAMLConfigurationEngineProtocol` stub: no filesystem, records what the
/// view model asks it to save. Possible only because the view model now depends on the
/// protocol rather than the concrete `YAMLConfigurationEngine`.
///
/// `@MainActor` matches the protocol's isolation (Core runs under
/// `defaultIsolation(MainActor.self)`).
@MainActor
private final class StubYAMLConfigurationEngine: YAMLConfigurationEngineProtocol {
    var configToReturn: YAMLConfigurationEngine.YAMLConfig
    private(set) var loadCallCount = 0
    private(set) var saveCallCount = 0
    private(set) var savedConfig: YAMLConfigurationEngine.YAMLConfig?
    private(set) var lastCreatedBackup = false

    init(config: YAMLConfigurationEngine.YAMLConfig = .init()) {
        self.configToReturn = config
    }

    func load() throws { loadCallCount += 1 }

    func getConfig() -> YAMLConfigurationEngine.YAMLConfig { configToReturn }

    func generateDiff(
        proposedConfig _: YAMLConfigurationEngine.YAMLConfig
    ) -> YAMLConfigurationEngine.ConfigDiff {
        YAMLConfigurationEngine.ConfigDiff(
            addedRules: [], removedRules: [], modifiedRules: [], before: "", after: ""
        )
    }

    func validate(_: YAMLConfigurationEngine.YAMLConfig) throws {}

    func save(config: YAMLConfigurationEngine.YAMLConfig, createBackup: Bool) throws {
        saveCallCount += 1
        savedConfig = config
        lastCreatedBackup = createBackup
    }
}

@MainActor
struct RuleDetailViewModelEngineProtocolTests {

    @Test("saveConfiguration enables the rule through the engine protocol — no disk I/O")
    func testSaveConfigurationPersistsEnableViaStub() throws {
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "force_cast", isOptIn: false)
        let stub = StubYAMLConfigurationEngine()
        let viewModel = RuleDetailViewModel(rule: rule, yamlEngine: stub)
        viewModel.isEnabled = true

        try viewModel.saveConfiguration()

        #expect(stub.loadCallCount == 1)
        #expect(stub.saveCallCount == 1)
        let saved = try #require(stub.savedConfig)
        #expect(saved.rules["force_cast"]?.enabled == true)
        #expect(stub.lastCreatedBackup)
    }

    @Test("saveConfiguration without an engine throws and writes nothing")
    func testSaveConfigurationWithoutEngineThrows() {
        let rule = RuleDetailViewModelTestHelpers.createTestRule(id: "force_cast", isOptIn: false)
        let viewModel = RuleDetailViewModel(rule: rule, yamlEngine: nil)

        #expect(throws: (any Error).self) {
            try viewModel.saveConfiguration()
        }
    }
}
