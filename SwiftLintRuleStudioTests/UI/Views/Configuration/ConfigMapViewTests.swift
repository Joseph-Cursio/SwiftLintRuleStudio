//
//  ConfigMapViewTests.swift
//  SwiftLintRuleStudioTests
//
//  ViewInspector tests for ConfigMapView — the sparse tree + resolved inspector
//  rendered from a loaded view model.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import SwiftUI
import Testing
import ViewInspector

@MainActor
struct ConfigMapViewTests {

    // MARK: - Helpers

    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigMapViewTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "opt_in_rules:\n  - force_unwrapping\n"
            .write(to: root.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        let testsDir = root.appendingPathComponent("Tests", isDirectory: true)
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try "disabled_rules:\n  - force_try\n"
            .write(to: testsDir.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        return root
    }

    private func texts(_ view: some View) throws -> [String] {
        ViewHosting.expel()
        ViewHosting.host(view: view)
        defer { ViewHosting.expel() }
        return try view.inspect()
            .findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }
    }

    // MARK: - Tests

    @Test("renders the config tree and the auto-selected root inspector")
    func testRendersTreeAndInspector() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let viewModel = ConfigMapViewModel(workspacePath: root)
        viewModel.load()

        let rendered = try texts(ConfigMapView(viewModel: viewModel))

        // Both config-bearing folders appear as tree rows.
        #expect(rendered.contains("root"))
        #expect(rendered.contains("Tests"))
        // The inspector shows the auto-selected root's layer chain.
        #expect(rendered.contains("Layer chain: root"))
    }

    @Test("renders the no-configs empty state for a workspace without .swiftlint.yml")
    func testEmptyState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigMapViewEmpty", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let viewModel = ConfigMapViewModel(workspacePath: root)
        viewModel.load()

        let rendered = try texts(ConfigMapView(viewModel: viewModel))
        #expect(rendered.contains("No SwiftLint Configs"))
    }
}
