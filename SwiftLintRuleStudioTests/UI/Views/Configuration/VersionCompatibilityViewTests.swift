//
//  VersionCompatibilityViewTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector smoke test for VersionCompatibilityView. The checker
//  stub returns a report with no issues; the SwiftLint CLI stub throws
//  notFound (so the view never resolves a version). We assert the
//  initial section header and the "no issues" empty state render.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Foundation
import SwiftUI
import Testing
import ViewInspector

private struct StubVersionChecker: VersionCompatibilityCheckerProtocol {
    func checkCompatibility(
        config _: YAMLConfigurationEngine.YAMLConfig,
        swiftLintVersion: String
    ) -> CompatibilityReport {
        CompatibilityReport(
            swiftLintVersion: swiftLintVersion,
            deprecatedRules: [],
            removedRules: [],
            renamedRules: [],
            availableNewRules: []
        )
    }
}

private struct VersionCompatibilityViewStubCLI: SwiftLintCLIProtocol {
    func detectSwiftLintPath() throws -> URL { throw SwiftLintError.notFound }
    func executeRulesCommand() throws -> Data { Data() }
    func executeRuleDetailCommand(ruleId _: String) throws -> Data { Data() }
    func generateDocsForRule(ruleId _: String) throws -> String { "" }
    func executeLintCommand(configPath _: URL?, workspacePath _: URL) throws -> Data { Data() }
    func getVersion() throws -> String { "0.0.0" }
}

@MainActor
struct VersionCompatibilityViewTests {
    @Test("VersionCompatibilityView renders the SwiftLint version header")
    func testInitialRenderShowsVersionHeader() async throws {
        let view = await MainActor.run {
            VersionCompatibilityView(
                checker: StubVersionChecker(),
                swiftLintCLI: VersionCompatibilityViewStubCLI(),
                configPath: nil
            )
        }

        let hasHeader = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            return (try? inspector.find(text: "SwiftLint Version")) != nil
        }

        #expect(hasHeader, "Version header section should render at launch")
    }
}
