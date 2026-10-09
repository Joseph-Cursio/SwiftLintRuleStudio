//
//  ConfigComparisonViewModelFolderTests.swift
//  SwiftLintRuleStudioTests
//
//  Choosing a project folder for comparison picks its .swiftlint.yml.
//

import Foundation
@testable import SwiftLintRuleStudio
@testable import SwiftLintRuleStudioCore
import Testing

@MainActor
struct ConfigComparisonViewModelFolderTests {
    private struct NoComparison: ConfigComparisonServiceProtocol {
        func compare(
            config1 _: URL,
            label1 _: String,
            config2 _: URL,
            label2 _: String
        ) throws -> ConfigComparisonResult {
            throw CancellationError()
        }
    }

    private func makeFolder(withConfig: Bool) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigComparisonFolderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if withConfig {
            try "excluded:\n  - build\n".write(
                to: folder.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8
            )
        }
        return folder
    }

    @Test("Choosing a project folder picks its .swiftlint.yml")
    func folderPicksItsConfig() throws {
        let folder = try makeFolder(withConfig: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let viewModel = ConfigComparisonViewModel(service: NoComparison(), currentWorkspace: nil) { folder }

        viewModel.selectRightWorkspace()

        #expect(viewModel.rightWorkspacePath == folder.appendingPathComponent(".swiftlint.yml"))
        #expect(viewModel.error == nil)
    }

    @Test("A folder without a .swiftlint.yml is an error, not a selection")
    func folderWithoutConfig() throws {
        let folder = try makeFolder(withConfig: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let viewModel = ConfigComparisonViewModel(service: NoComparison(), currentWorkspace: nil) { folder }

        viewModel.selectLeftWorkspace()

        #expect(viewModel.leftWorkspacePath == nil)
        #expect(viewModel.error?.localizedDescription.contains("has no .swiftlint.yml") == true)
    }

    @Test("Choosing the file itself still works")
    func fileStillWorks() throws {
        let folder = try makeFolder(withConfig: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(".swiftlint.yml")
        let viewModel = ConfigComparisonViewModel(service: NoComparison(), currentWorkspace: nil) { file }

        viewModel.selectLeftWorkspace()

        #expect(viewModel.leftWorkspacePath == file)
    }

    @Test("Each side is named after its folder")
    func labelsAreFolderNames() {
        let labels = ConfigComparisonViewModel.labels(
            for: URL(fileURLWithPath: "/work/MacCloud_server/.swiftlint.yml"),
            URL(fileURLWithPath: "/work/MacCloud_client_MacOS/.swiftlint.yml")
        )
        #expect(labels == ("MacCloud_server", "MacCloud_client_MacOS"))
    }

    @Test("Folders with the same name are told apart", arguments: [
        ("/work/MyApp/.swiftlint.yml", "/old/MyApp/.swiftlint.yml", "work/MyApp", "old/MyApp"),
        ("/a/MyApp/.swiftlint.yml", "/x/a/MyApp/.swiftlint.yml", "a/MyApp", "x/a/MyApp"),
        ("/Downloads/strict.yml", "/Downloads/lenient.yml", "strict.yml", "lenient.yml"),
        ("/work/MyApp/.swiftlint.yml", "/work/MyApp/.swiftlint.yml", "Left", "Right")
    ])
    func labelsAreToldApart(left: String, right: String, leftLabel: String, rightLabel: String) {
        let labels = ConfigComparisonViewModel.labels(
            for: URL(fileURLWithPath: left), URL(fileURLWithPath: right)
        )
        #expect(labels == (leftLabel, rightLabel))
    }
}
