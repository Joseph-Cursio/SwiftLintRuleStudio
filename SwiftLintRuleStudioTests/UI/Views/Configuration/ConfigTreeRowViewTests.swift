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
            id: URL(fileURLWithPath: "/ws/Tests/.swiftlint.yml"),
            displayName: "Tests",
            relativePath: "Tests/.swiftlint.yml",
            indentLevel: 1,
            isRoot: false,
            badge: "-2 disabled",
            hasIneffectiveExclusions: false,
            hasParseError: false,
            replaces: nil,
            pullsIn: []
        )

        let rendered = try texts(ConfigTreeRowView(row: row))
        #expect(rendered.contains("Tests"))
        #expect(rendered.contains("-2 disabled"))
    }

    @Test("root row renders without a badge when none is provided")
    func testRootNoBadge() throws {
        let row = ConfigTreeRow(
            id: URL(fileURLWithPath: "/ws/.swiftlint.yml"),
            displayName: "root",
            relativePath: ".swiftlint.yml",
            indentLevel: 0,
            isRoot: true,
            badge: nil,
            hasIneffectiveExclusions: false,
            hasParseError: false,
            replaces: nil,
            pullsIn: []
        )

        let rendered = try texts(ConfigTreeRowView(row: row))
        #expect(rendered.contains("root"))
        #expect(rendered.contains { $0.hasPrefix("replaces") } == false)
    }

    @Test("a config nested in another nested config says which one it replaces")
    func testReplacesNote() throws {
        let row = ConfigTreeRow(
            id: URL(fileURLWithPath: "/ws/Sub/Deeper/.swiftlint.yml"),
            displayName: "Deeper",
            relativePath: "Sub/Deeper/.swiftlint.yml",
            indentLevel: 2,
            isRoot: false,
            badge: "-1 disabled",
            hasIneffectiveExclusions: false,
            hasParseError: false,
            replaces: "Sub",
            pullsIn: []
        )

        let rendered = try texts(ConfigTreeRowView(row: row))
        #expect(rendered.contains("Deeper"))
        #expect(rendered.contains("replaces Sub"))
    }

    @Test("the root row names the configs it pulls in from beyond the workspace")
    func testPullsInNote() throws {
        let row = ConfigTreeRow(
            id: URL(fileURLWithPath: "/ws/.swiftlint.yml"),
            displayName: "root",
            relativePath: ".swiftlint.yml",
            indentLevel: 0,
            isRoot: true,
            badge: "-1 disabled",
            hasIneffectiveExclusions: false,
            hasParseError: false,
            replaces: nil,
            pullsIn: ["../../.swiftlint.yml", "https://example.com/strict.yml"]
        )

        let rendered = try texts(ConfigTreeRowView(row: row))
        #expect(rendered.contains("pulls in ../../.swiftlint.yml, https://example.com/strict.yml"))
    }
}
