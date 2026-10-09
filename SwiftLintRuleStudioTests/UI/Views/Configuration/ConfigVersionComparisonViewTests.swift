//
//  ConfigVersionComparisonViewTests.swift
//  SwiftLintRuleStudioTests
//
//  The pieces of a version comparison: the swap arrow, the Current row, and a restore button
//  that can be left out.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct ConfigVersionComparisonViewTests {
    private final class Taps {
        var count = 0
    }

    private func texts(_ view: some View) throws -> [String] {
        try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    @Test("The arrow between the two versions swaps them")
    func arrowSwaps() throws {
        let taps = Taps()
        let header = ConfigVersionDiffHeaderRow(before: "Current", after: "Oct 9, 2026 at 12:09 PM") {
            taps.count += 1
        }

        try header.inspect().find(ViewType.Button.self).tap()

        #expect(taps.count == 1)
    }

    @Test("The current configuration's row says what it is")
    func currentRow() throws {
        let row = BackupRow(
            backup: ConfigBackup(
                id: "current",
                path: URL(fileURLWithPath: "/tmp/.swiftlint.yml"),
                timestamp: .now,
                fileSize: 559
            ),
            isSelected: false,
            isComparison: false,
            isCurrent: true,
            onSelect: {},
            onRestore: {}
        )

        let rendered = try texts(row)
        #expect(rendered.contains("Current"))
        #expect(rendered.contains { $0.hasPrefix("Your .swiftlint.yml as it is now") })
    }

    @Test("A comparison with nothing to restore shows no restore button")
    func noRestoreButton() throws {
        let view = ConfigDiffPreviewView(
            diff: YAMLConfigurationEngine.ConfigDiff(
                addedRules: [], removedRules: [], modifiedRules: [], before: "a", after: "b",
                changes: ConfigChangeSummary(turnedOn: ["empty_count"])
            ),
            ruleName: "Version Comparison",
            onSave: {},
            onCancel: {},
            isInline: true,
            saveLabel: "",
            cancelLabel: "Clear Comparison",
            showsSave: false
        )

        let rendered = try texts(view)
        #expect(rendered.contains("Clear Comparison"))
        #expect(!rendered.contains("Save Changes"))
        #expect(try view.inspect().findAll(ViewType.Button.self).count == 2, "Copy for PR and Clear Comparison")
    }

    @Test("The restore button restores the after version, swapped or not")
    func restoreButtonRestoresAfterSide() throws {
        let older = ConfigBackup(
            id: "older", path: URL(fileURLWithPath: "/tmp/a"), timestamp: .distantPast, fileSize: 1
        )
        let newer = ConfigBackup(id: "newer", path: URL(fileURLWithPath: "/tmp/b"), timestamp: .now, fileSize: 1)
        let viewModel = ConfigVersionHistoryViewModel(
            service: SpyVersionHistoryService(backups: [older, newer]),
            configPath: URL(fileURLWithPath: "/tmp/none.yml")
        )
        viewModel.selectForComparison(older)
        viewModel.selectForComparison(newer)
        viewModel.swapComparison()

        let detail = ConfigVersionHistoryDiffDetailView(viewModel: viewModel)
        try detail.inspect().find(button: "Restore Older Version").tap()

        #expect(viewModel.backupToRestore?.id == older.id)
    }
}
