//
//  XcodeIntegrationServiceLaunchTests.swift
//  SwiftLintRuleStudioTests
//
//  What XcodeIntegrationService launches to open a file, and in which order it
//  falls back, observed through a recording launcher — no test starts Xcode.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

struct XcodeIntegrationServiceLaunchTests {

    /// Opens the minimal workspace's `TestFile.swift` through `launcher` and
    /// returns what `openFile` answered, with the path the service resolved.
    @MainActor
    private func openTestFile(
        with launcher: RecordingXcodeLauncher,
        line: Int = 7,
        column: Int? = nil
    ) throws -> (opened: Bool, path: String) {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }

        let service = XcodeIntegrationService(launcher: launcher)
        let opened = try service.openFile(
            at: "TestFile.swift",
            line: line,
            column: column,
            in: Workspace(path: workspace)
        )
        let path = workspace.appendingPathComponent("TestFile.swift").standardizedFileURL.path
        return (opened, path)
    }

    @Test("Opens the file with xed at its line, and launches nothing else")
    @MainActor
    func testOpensWithXedFirst() throws {
        let launcher = RecordingXcodeLauncher()

        let (opened, path) = try openTestFile(with: launcher, line: 7)

        #expect(opened)
        #expect(launcher.xedRuns == [["--line", "7", path]])
        #expect(launcher.openedURLs.isEmpty)
    }

    @Test("Falls back to the xcode:// URL when xed cannot start")
    @MainActor
    func testFallsBackToXcodeURL() throws {
        let launcher = RecordingXcodeLauncher(xedSucceeds: false)

        let (opened, path) = try openTestFile(with: launcher, line: 12, column: 4)

        #expect(opened)
        #expect(launcher.xedRuns.count == 1)
        #expect(launcher.openedURLs.count == 1)
        let components = launcher.openedURLs.first.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }
        #expect(components?.scheme == "xcode")
        #expect(components?.host == "file")
        #expect(components?.queryItems == [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "line", value: "12"),
            URLQueryItem(name: "column", value: "4")
        ])
    }

    @Test("Falls back to opening the file itself when the xcode:// URL is refused")
    @MainActor
    func testFallsBackToFileURL() throws {
        let launcher = RecordingXcodeLauncher(xedSucceeds: false, xcodeURLOpens: false)

        let (opened, path) = try openTestFile(with: launcher)

        #expect(opened)
        #expect(launcher.openedURLs.map(\.scheme) == ["xcode", "file"])
        #expect(launcher.openedURLs.last?.path == path)
    }

    @Test("Throws failedToOpen when every method is refused")
    @MainActor
    func testThrowsWhenNothingOpens() throws {
        let launcher = RecordingXcodeLauncher(xedSucceeds: false, xcodeURLOpens: false, fileURLOpens: false)

        #expect {
            try openTestFile(with: launcher)
        } throws: { error in
            guard case XcodeIntegrationError.failedToOpen = error else { return false }
            return true
        }
        #expect(launcher.xedRuns.count == 1)
        #expect(launcher.openedURLs.count == 2)
    }

    @Test("Launches nothing for a file that does not exist")
    @MainActor
    func testLaunchesNothingForMissingFile() throws {
        let workspace = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(workspace) }
        let launcher = RecordingXcodeLauncher()
        let service = XcodeIntegrationService(launcher: launcher)

        #expect(throws: XcodeIntegrationError.self) {
            try service.openFile(at: "Missing.swift", line: 1, column: nil, in: Workspace(path: workspace))
        }
        #expect(launcher.xedRuns.isEmpty)
        #expect(launcher.openedURLs.isEmpty)
    }
}
