//
//  ConfigVersionHistoryViewModelLegacyTests.swift
//  SwiftLintRuleStudioTests
//
//  Version History against the real service and a store in a temporary folder: backups an
//  earlier version left in the project folder are shown, and moved out only on request.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

@MainActor
struct ConfigVersionHistoryViewModelLegacyTests {

    private struct Fixture {
        let project: URL
        let config: URL
        let store: ConfigBackupStore
        let viewModel: ConfigVersionHistoryViewModel
    }

    private func makeFixture(
        legacy seconds: [Int],
        discard: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) throws -> Fixture {
        let base = TestTempDirectory.make("history-legacy")
        let project = base.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let config = project.appendingPathComponent(".swiftlint.yml")
        try "rules: {}\n".write(to: config, atomically: true, encoding: .utf8)
        for second in seconds {
            try "disabled_rules:\n  - rule_\(second)\n".write(
                to: project.appendingPathComponent(".swiftlint.yml.\(second).backup"),
                atomically: true,
                encoding: .utf8
            )
        }
        let store = ConfigBackupStore(root: base.appendingPathComponent("store", isDirectory: true))
        // Deletes rather than trashes, so a test run doesn't fill the developer's Trash.
        let service = ConfigVersionHistoryService(backups: store, discard: discard)
        return Fixture(
            project: project,
            config: config,
            store: store,
            viewModel: ConfigVersionHistoryViewModel(service: service, configPath: config)
        )
    }

    @Test("the hosted app's test run never writes backups into the real Application Support")
    func standardStoreIsTemporaryInHostedTests() {
        let root = ConfigBackupStore.standard.root.path
        #expect(root.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(!root.contains("/Library/Application Support/"))
    }

    @Test("backups in the project folder are listed and counted, and nothing moves on its own")
    func legacyBackupsAreShownNotMoved() throws {
        let fixture = try makeFixture(legacy: [1_700_000_000, 1_700_000_100])

        fixture.viewModel.loadBackups()

        #expect(fixture.viewModel.backups.count == 2)
        #expect(fixture.viewModel.legacyBackupCount == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.project.path).count == 3)
        #expect(fixture.viewModel.backupsFolder == nil, "the store holds nothing for this file yet")
    }

    @Test("moving them out empties the project folder and keeps the history")
    func moveLegacyBackups() throws {
        let fixture = try makeFixture(legacy: [1_700_000_000, 1_700_000_100])
        fixture.viewModel.loadBackups()

        fixture.viewModel.moveLegacyBackups()

        #expect(fixture.viewModel.error == nil)
        #expect(fixture.viewModel.legacyBackupCount == 0)
        #expect(fixture.viewModel.backups.map(\.timestamp) == [
            Date(timeIntervalSince1970: 1_700_000_100),
            Date(timeIntervalSince1970: 1_700_000_000)
        ])
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.project.path) == [".swiftlint.yml"])
        #expect(fixture.viewModel.backupsFolder?.resolvingSymlinksInPath()
            == fixture.store.directory(for: fixture.config).resolvingSymlinksInPath())
    }

    @Test("a backup that couldn't go to the Trash stays put, and says so")
    func failedMoveReportsIt() throws {
        struct TrashRefused: Error {}
        let fixture = try makeFixture(legacy: [1_700_000_000]) { _ in throw TrashRefused() }
        fixture.viewModel.loadBackups()

        fixture.viewModel.moveLegacyBackups()

        #expect(fixture.viewModel.legacyBackupCount == 1)
        #expect(fixture.viewModel.error is LegacyBackupsNotMovedError)
        #expect(fixture.viewModel.backups.count == 1)
    }

    @Test("selections that name moved backups are dropped, with their comparison")
    func moveClearsStaleSelections() throws {
        let fixture = try makeFixture(legacy: [1_700_000_000, 1_700_000_100])
        fixture.viewModel.loadBackups()
        fixture.viewModel.selectForComparison(fixture.viewModel.backups[1])
        fixture.viewModel.selectForComparison(fixture.viewModel.backups[0])
        #expect(fixture.viewModel.currentDiff != nil)

        fixture.viewModel.moveLegacyBackups()

        #expect(fixture.viewModel.selectedBackup == nil)
        #expect(fixture.viewModel.comparisonBackup == nil)
        #expect(fixture.viewModel.currentDiff == nil)
    }
}
