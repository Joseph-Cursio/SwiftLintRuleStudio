//
//  BackupRowTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector smoke test for BackupRow. We construct a known
//  ConfigBackup and assert the formatted date + size strings the row
//  exposes via Text() render in the hosted view.
//

@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Foundation
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct BackupRowTests {
    @Test("BackupRow renders the backup's formatted date and size")
    func testRendersFormattedDateAndSize() async throws {
        let backup = ConfigBackup(
            id: "test-backup",
            path: URL(fileURLWithPath: "/tmp/.swiftlint.yml.bak"),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            fileSize: 2048
        )
        let view = await MainActor.run {
            BackupRow(
                backup: backup,
                isSelected: false,
                isComparison: false,
                onSelect: {},
                onRestore: {}
            )
        }

        let (hasDate, hasSize) = try await MainActor.run {
            ViewHosting.expel()
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let inspector = try view.inspect()
            return (
                (try? inspector.find(text: backup.formattedDate)) != nil,
                (try? inspector.find(text: backup.formattedSize)) != nil
            )
        }

        #expect(hasDate, "Formatted timestamp should render")
        #expect(hasSize, "Formatted size string (\(backup.formattedSize)) should render")
    }
}
