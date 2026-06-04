//
//  ConfigMapViewModelTests.swift
//  SwiftLintRuleStudioTests
//
//  Tests for ConfigMapViewModel — discovering the config tree and resolving the
//  selected folder's effective config. Uses a real temp workspace (the Core
//  engines are fast and deterministic).
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct ConfigMapViewModelTests {

    // MARK: - Helpers

    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigMapVMTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @discardableResult
    private func writeConfig(_ content: String, at relativeDirectory: String, in root: URL) throws -> URL {
        let directory = relativeDirectory.isEmpty
            ? root
            : root.appendingPathComponent(relativeDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configPath = directory.appendingPathComponent(".swiftlint.yml")
        try content.write(to: configPath, atomically: true, encoding: .utf8)
        return configPath
    }

    private func cleanup(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeLayeredWorkspace() throws -> URL {
        let root = try makeWorkspace()
        try writeConfig("opt_in_rules:\n  - force_unwrapping\n", at: "", in: root)
        try writeConfig("disabled_rules:\n  - force_try\n  - force_unwrapping\n", at: "Tests", in: root)
        return root
    }

    // MARK: - Tests

    @Test("load discovers the tree and auto-selects the root config")
    func testLoadSelectsRoot() throws {
        let root = try makeLayeredWorkspace()
        defer { cleanup(root) }

        let viewModel = ConfigMapViewModel(workspacePath: root)
        viewModel.load()

        #expect(viewModel.hasWorkspace)
        #expect(viewModel.treeRows.map(\.displayName) == ["root", "Tests"])
        #expect(viewModel.selectedRowID == viewModel.treeRows.first?.id)
        #expect(viewModel.resolvedDisplay?.targetLabel == "root")
    }

    @Test("selecting a nested config resolves its effective config")
    func testSelectNestedConfig() throws {
        let root = try makeLayeredWorkspace()
        defer { cleanup(root) }

        let viewModel = ConfigMapViewModel(workspacePath: root)
        viewModel.load()

        let testsRow = try #require(viewModel.treeRows.first { $0.displayName == "Tests" })
        viewModel.select(rowID: testsRow.id)

        let display = try #require(viewModel.resolvedDisplay)
        #expect(display.targetLabel == "Tests")
        #expect(display.layerChainLabels == ["root", "Tests"])
        let forceUnwrapping = display.ruleRows.first { $0.id == "force_unwrapping" }
        #expect(forceUnwrapping?.state == "off (disabled)")
        #expect(forceUnwrapping?.setBy == "Tests")
    }

    @Test("a custom rule shadowing a built-in is flagged on the selected config")
    func testCustomRuleConflictDetected() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig(#"""
        opt_in_rules:
          - force_unwrapping
        custom_rules:
          leading_whitespace:
            name: Tabs
            regex: ^\t* +\t*\S
            severity: error
        """#, at: "", in: root)

        let viewModel = ConfigMapViewModel(
            workspacePath: root,
            builtInRuleIdentifiers: ["leading_whitespace", "force_cast"]
        )
        viewModel.load()

        #expect(viewModel.conflicts.map(\.ruleIdentifier) == ["leading_whitespace"])
    }

    @Test("no conflict when custom rule names are unique")
    func testNoCustomRuleConflict() throws {
        let root = try makeWorkspace()
        defer { cleanup(root) }
        try writeConfig(#"""
        custom_rules:
          tab_indentation:
            name: Tabs
            regex: ^\t* +\t*\S
        """#, at: "", in: root)

        let viewModel = ConfigMapViewModel(
            workspacePath: root,
            builtInRuleIdentifiers: ["leading_whitespace"]
        )
        viewModel.load()

        #expect(viewModel.conflicts.isEmpty)
    }

    @Test("no workspace yields an empty, inert map")
    func testNoWorkspace() {
        let viewModel = ConfigMapViewModel(workspacePath: nil)
        viewModel.load()

        #expect(viewModel.hasWorkspace == false)
        #expect(viewModel.treeRows.isEmpty)
        #expect(viewModel.resolvedDisplay == nil)
    }
}
