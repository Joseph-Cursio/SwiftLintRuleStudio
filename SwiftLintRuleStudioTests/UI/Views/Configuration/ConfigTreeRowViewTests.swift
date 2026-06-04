//
//  ConfigTreeRowViewTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector tests for ConfigTreeRowView — a single sparse-tree row.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct ConfigTreeRowViewTests {
    private func texts(_ view: some View) throws -> [String] {
        ViewHosting.expel()
        ViewHosting.host(view: view)
        defer { ViewHosting.expel() }
        return try view.inspect()
            .findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }
    }

    @Test("renders the display name and badge")
    func testNameAndBadge() throws {
        let row = ConfigTreeRow(
            id: UUID(),
            displayName: "Tests",
            relativePath: "Tests/.swiftlint.yml",
            indentLevel: 1,
            isRoot: false,
            badge: "-2 disabled",
            hasIneffectiveExclusions: false,
            hasParseError: false
        )

        let rendered = try texts(ConfigTreeRowView(row: row))
        #expect(rendered.contains("Tests"))
        #expect(rendered.contains("-2 disabled"))
    }

    @Test("root row renders without a badge when none is provided")
    func testRootNoBadge() throws {
        let row = ConfigTreeRow(
            id: UUID(),
            displayName: "root",
            relativePath: ".swiftlint.yml",
            indentLevel: 0,
            isRoot: true,
            badge: nil,
            hasIneffectiveExclusions: false,
            hasParseError: false
        )

        let rendered = try texts(ConfigTreeRowView(row: row))
        #expect(rendered.contains("root"))
    }
}
