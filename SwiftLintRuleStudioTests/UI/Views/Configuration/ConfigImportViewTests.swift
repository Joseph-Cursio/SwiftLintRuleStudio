//
//  ConfigImportViewTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector smoke test for ConfigImportView. The stub doesn't need
//  to do anything for the initial render: the view shows its
//  "Import from URL" section + mode picker without first fetching.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Foundation
import SwiftUI
import Testing
import ViewInspector

private struct StubConfigImportService: ConfigImportServiceProtocol {
    func fetchAndPreview(from url: URL, currentConfigPath _: URL?) async throws -> ConfigImportPreview {
        ConfigImportPreview(
            sourceURL: url,
            fetchedYAML: "",
            parsedConfig: YAMLConfigurationEngine.YAMLConfig(),
            diff: nil,
            validationErrors: []
        )
    }

    func applyImport(preview _: ConfigImportPreview, mode _: ImportMode, to _: URL) throws {}
}

@MainActor
struct ConfigImportViewTests {
    @Test("ConfigImportView renders the URL section and import-mode options at launch")
    func testInitialRenderShowsURLSectionAndModes() async throws {
        let view = await MainActor.run {
            ConfigImportView(importService: StubConfigImportService(), configPath: nil)
        }

        let (hasUrlHeader, hasMergeMode, hasReplaceMode) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            return (
                (try? inspector.find(text: "Import from URL")) != nil,
                (try? inspector.find(text: "Merge (imported rules override conflicts)")) != nil,
                (try? inspector.find(text: "Replace (replace entire config)")) != nil
            )
        }

        #expect(hasUrlHeader)
        #expect(hasMergeMode)
        #expect(hasReplaceMode)
    }
}
