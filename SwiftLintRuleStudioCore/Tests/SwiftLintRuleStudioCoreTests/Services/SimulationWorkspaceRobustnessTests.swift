//
//  SimulationWorkspaceRobustnessTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Building a simulation mirror must stay bounded, stop when cancelled, skip what it can't
//  read rather than fail, and leave no container behind — even ones an earlier run abandoned.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct SimulationWorkspaceRobustnessTests {

    /// Puts the mirrors this test makes in its own temp folder, so it can count them.
    nonisolated private final class IsolatedFileManager: FileManager, @unchecked Sendable {
        let folder: URL

        init(folder: URL) {
            self.folder = folder
            super.init()
        }

        override var temporaryDirectory: URL { folder }
    }

    private struct Fixture {
        let base: URL
        let workspace: URL
        let kit: URL
        let fileManager: IsolatedFileManager

        /// The mirrors left in this fixture's temp folder.
        var containers: [URL] {
            let parent = fileManager.folder.appendingPathComponent("SwiftLintRuleStudio")
            return (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
        }
    }

    private func makeFixture(kitFiles: Int = 3) throws -> Fixture {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowRobustnessTests-\(UUID().uuidString)", isDirectory: true)
        let workspace = base.appendingPathComponent("ws", isDirectory: true)
        let kit = base.appendingPathComponent("kit", isDirectory: true)
        let temp = base.appendingPathComponent("tmp", isDirectory: true)
        for folder in [workspace.appendingPathComponent("Sources"), kit, temp] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try write("excluded:\n  - Nope\n", to: workspace.appendingPathComponent(".swiftlint.yml"))
        try write("let a = 1\n", to: workspace.appendingPathComponent("Sources/A.swift"))
        for index in 0..<kitFiles {
            try write("let k = \(index)\n", to: kit.appendingPathComponent("K\(index).swift"))
        }
        try FileManager.default.createSymbolicLink(
            atPath: workspace.appendingPathComponent("Sources/Kit").path,
            withDestinationPath: "../../kit"
        )
        return Fixture(base: base, workspace: workspace, kit: kit, fileManager: IsolatedFileManager(folder: temp))
    }

    private func write(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func builder(
        _ fixture: Fixture,
        limit: Int = MirrorLinkDiscovery.outsideEntryLimit
    ) -> SimulationWorkspaceBuilder {
        SimulationWorkspaceBuilder(fileManager: fixture.fileManager, outsideEntryLimit: limit)
    }

    private func mirror(
        _ fixture: Fixture,
        limit: Int = MirrorLinkDiscovery.outsideEntryLimit
    ) throws -> SimulationWorkspace {
        try builder(fixture, limit: limit).makeWorkspace(for: Workspace(path: fixture.workspace), baseConfigPath: nil)
    }

    private func mirrored(_ path: String, in shadow: SimulationWorkspace) -> Bool {
        FileManager.default.fileExists(atPath: shadow.root.appendingPathComponent(path).path)
    }

    // MARK: - Bounds

    @Test("links leading to more outside the workspace than the limit stop the mirror and leave no container")
    func tooMuchOutsideStops() throws {
        let fixture = try makeFixture(kitFiles: 3)
        defer { try? FileManager.default.removeItem(at: fixture.base) }

        let error = #expect(throws: MirrorTooLargeError.self) {
            _ = try mirror(fixture, limit: 2)
        }

        #expect(error?.link == "Sources/Kit")
        #expect(error?.localizedDescription.contains("Sources/Kit") == true)
        #expect(fixture.containers.isEmpty)
    }

    @Test("within the limit the outside folder is mirrored")
    func withinTheLimitMirrors() throws {
        let fixture = try makeFixture(kitFiles: 3)
        defer { try? FileManager.default.removeItem(at: fixture.base) }

        let shadow = try mirror(fixture, limit: 10)
        defer { shadow.cleanup() }

        #expect(mirrored("Sources/Kit/K2.swift", in: shadow))
    }

    // MARK: - Cancellation

    @Test("a cancelled mirror stops and leaves no container")
    func cancelledMirrorStops() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let builder = builder(fixture)
        let workspace = Workspace(path: fixture.workspace)

        let build = Task { try builder.makeWorkspace(for: workspace, baseConfigPath: nil) }
        build.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await build.value
        }
        #expect(fixture.containers.isEmpty)
    }

    @Test("building the mirror off the main actor stops when its task is cancelled")
    func cancelledAsyncMirrorStops() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let builder = SimulationWorkspaceBuilder()
        let workspace = Workspace(path: fixture.workspace)

        let build = Task { () async throws -> SimulationWorkspace in
            try await builder.makeWorkspace(for: workspace, baseConfigPath: nil)
        }
        build.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await build.value
        }
    }

    // MARK: - Leftovers

    @Test("a file that can be neither linked nor read is left out, as SwiftLint leaves it out")
    func unreadableFileIsSkipped() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let locked = fixture.workspace.appendingPathComponent("Sources/Locked.swift")
        try write("let l = 1\n", to: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0, .immutable: true], ofItemAtPath: locked.path)
        defer {
            let unlocked: [FileAttributeKey: Any] = [.immutable: false, .posixPermissions: 0o644]
            try? FileManager.default.setAttributes(unlocked, ofItemAtPath: locked.path)
        }

        let shadow = try mirror(fixture)
        defer { shadow.cleanup() }

        #expect(mirrored("Sources/A.swift", in: shadow))
        #expect(!mirrored("Sources/Locked.swift", in: shadow))
    }

    @Test("a Finder-locked file copied in is unlocked, so the mirror can be removed")
    func lockedCopyIsUnlocked() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let locked = fixture.workspace.appendingPathComponent("Sources/Locked.swift")
        try write("let l = 1\n", to: locked)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: locked.path) }

        let shadow = try mirror(fixture)
        #expect(mirrored("Sources/Locked.swift", in: shadow))
        shadow.cleanup()

        #expect(fixture.containers.isEmpty)
        let stillLocked = try FileManager.default.attributesOfItem(atPath: locked.path)[.immutable] as? Bool
        #expect(stillLocked == true, "the user's file keeps its lock")
    }

    @Test("a new simulation sweeps containers abandoned a day ago, and leaves recent ones")
    func abandonedContainersAreSwept() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let parent = fixture.fileManager.folder.appendingPathComponent("SwiftLintRuleStudio")
        let abandoned = parent.appendingPathComponent("abandoned")
        let recent = parent.appendingPathComponent("recent")
        for folder in [abandoned, recent] {
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("ws"),
                withIntermediateDirectories: true
            )
        }
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        try FileManager.default.setAttributes(
            [.creationDate: twoDaysAgo, .modificationDate: twoDaysAgo],
            ofItemAtPath: abandoned.path
        )

        let shadow = try mirror(fixture)
        defer { shadow.cleanup() }

        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
    }
}
