//
//  ConfigVersionHistoryViewTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector smoke test for ConfigVersionHistoryView. The service
//  stub returns no backups so the view renders its empty state, which
//  is what we assert on.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

private struct StubConfigVersionHistoryService: ConfigVersionHistoryServiceProtocol {
    func listBackups(for _: URL) -> [ConfigBackup] { [] }
    func loadBackup(_: ConfigBackup) throws -> String { "" }
    func restoreBackup(_: ConfigBackup, to _: URL) throws {}
    func diffBetween(_: ConfigBackup, _: ConfigBackup) throws -> YAMLConfigurationEngine.ConfigDiff {
        YAMLConfigurationEngine.ConfigDiff(
            addedRules: [], removedRules: [], modifiedRules: [],
            before: "", after: ""
        )
    }
    func pruneOldBackups(for _: URL, keepCount _: Int) throws {}
}

@MainActor
struct ConfigVersionHistoryViewTests {
    @Test("ConfigVersionHistoryView renders the empty-state copy when there are no backups")
    func testEmptyState() async throws {
        let view = await MainActor.run {
            ConfigVersionHistoryView(service: StubConfigVersionHistoryService(), configPath: nil)
        }

        let hasEmptyMessage = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            return (try? inspector.find(text: "Configuration backups will appear here after you save changes.")) != nil
        }

        #expect(hasEmptyMessage, "Empty-state message should render when no backups exist")
    }
}
