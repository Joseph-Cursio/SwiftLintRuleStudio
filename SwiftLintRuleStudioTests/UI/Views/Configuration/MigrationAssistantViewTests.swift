//
//  MigrationAssistantViewTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector smoke tests for MigrationAssistantView. The stubs return
//  the "no migrations needed" plan so the view renders its empty-state
//  branch, which lets us assert the section headers it shows by default.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Foundation
import SwiftUI
import Testing
import ViewInspector

private struct StubMigrationAssistant: MigrationAssistantProtocol {
    func detectMigrations(
        config _: YAMLConfigurationEngine.YAMLConfig,
        fromVersion: String,
        toVersion: String
    ) -> MigrationPlan {
        MigrationPlan(fromVersion: fromVersion, toVersion: toVersion, steps: [])
    }

    func applyMigration(
        _: MigrationPlan,
        to _: inout YAMLConfigurationEngine.YAMLConfig
    ) {}
}

private struct MigrationAssistantViewStubCLI: SwiftLintCLIProtocol {
    func detectSwiftLintPath() throws -> URL { throw SwiftLintError.notFound }
    func executeRulesCommand() throws -> Data { Data() }
    func executeRuleDetailCommand(ruleId _: String) throws -> Data { Data() }
    func generateDocsForRule(ruleId _: String) throws -> String { "" }
    func executeLintCommand(configPath _: URL?, workspacePath _: URL) throws -> Data { Data() }
    func getVersion() throws -> String { "0.0.0" }
}

@MainActor
struct MigrationAssistantViewTests {
    @Test("MigrationAssistantView renders Version Migration / Migration Plan section headers")
    func testInitialRenderShowsSectionHeaders() async throws {
        let view = await MainActor.run {
            MigrationAssistantView(
                assistant: StubMigrationAssistant(),
                swiftLintCLI: MigrationAssistantViewStubCLI(),
                configPath: nil
            )
        }

        let (hasVersionMigration, hasPreviousVersion, hasCurrentVersion) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            return (
                (try? inspector.find(text: "Version Migration")) != nil,
                (try? inspector.find(text: "Previous Version")) != nil,
                (try? inspector.find(text: "Current Version")) != nil
            )
        }

        #expect(hasVersionMigration)
        #expect(hasPreviousVersion)
        #expect(hasCurrentVersion)
    }
}
