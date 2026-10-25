//
//  SimulationWorkspaceLifetimeTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  A live mirror survives a sweep however old it looks; the bound counts what will be copied;
//  a file that can't be copied fails the mirror rather than go missing from it.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

struct SimulationWorkspaceLifetimeTests {

    // MARK: - Helpers

    /// Puts the mirrors a test makes in its own temp folder, and can be told to fail copies.
    nonisolated private final class IsolatedFileManager: FileManager, @unchecked Sendable {
        let folder: URL
        let failsCopies: Bool

        init(folder: URL, failsCopies: Bool = false) {
            self.folder = folder
            self.failsCopies = failsCopies
            super.init()
        }

        override var temporaryDirectory: URL { folder }

        override func linkItem(at srcURL: URL, to dstURL: URL) throws {
            guard !failsCopies else { throw CocoaError(.fileWriteUnknown) }
            try super.linkItem(at: srcURL, to: dstURL)
        }

        override func copyItem(at srcURL: URL, to dstURL: URL) throws {
            guard !failsCopies else { throw CocoaError(.fileWriteOutOfSpace) }
            try super.copyItem(at: srcURL, to: dstURL)
        }
    }

    /// `<base>/ws`, with `Sources/Kit` linking to `<base>/kit`, mirrored into `<base>/tmp`.
    private struct Fixture {
        let base: URL
        let workspace: URL
        let temp: URL

        var mirrors: URL { temp.appendingPathComponent("SwiftLintRuleStudio") }

        var containers: [URL] {
            (try? FileManager.default.contentsOfDirectory(at: mirrors, includingPropertiesForKeys: nil)) ?? []
        }
    }

    private func makeFixture(config: String = "excluded:\n  - Nope\n", kitFiles: Int = 3) throws -> Fixture {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowLifetimeTests-\(UUID().uuidString)", isDirectory: true)
        let fixture = Fixture(
            base: base,
            workspace: base.appendingPathComponent("ws", isDirectory: true),
            temp: base.appendingPathComponent("tmp", isDirectory: true)
        )
        try FileManager.default.createDirectory(at: fixture.temp, withIntermediateDirectories: true)
        try write(config, to: fixture.workspace.appendingPathComponent(".swiftlint.yml"))
        try write("let a = 1\n", to: fixture.workspace.appendingPathComponent("Sources/A.swift"))
        for index in 0..<kitFiles {
            try write("let k = \(index)\n", to: base.appendingPathComponent("kit/K\(index).swift"))
        }
        try FileManager.default.createSymbolicLink(
            atPath: fixture.workspace.appendingPathComponent("Sources/Kit").path,
            withDestinationPath: "../../kit"
        )
        return fixture
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func mirror(
        _ fixture: Fixture,
        limit: Int = MirrorLinkDiscovery.outsideEntryLimit,
        failsCopies: Bool = false
    ) throws -> SimulationWorkspace {
        try SimulationWorkspaceBuilder(
            fileManager: IsolatedFileManager(folder: fixture.temp, failsCopies: failsCopies),
            outsideEntryLimit: limit
        ).makeWorkspace(for: Workspace(path: fixture.workspace), baseConfigPath: nil)
    }

    private func backdate(_ folder: URL, days: Double) throws {
        let date = Date().addingTimeInterval(-days * 24 * 60 * 60)
        try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: folder.path)
    }

    // MARK: - The lock

    @Test("a lock is held from acquiring it until it is released")
    func lockIsHeldUntilReleased() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MirrorLockTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(!MirrorLock.isHeld(in: folder), "no lock file yet")
        let lock = try MirrorLock.acquire(in: folder)
        #expect(MirrorLock.isHeld(in: folder))
        #expect(throws: (any Error).self) { try MirrorLock.acquire(in: folder) }
        lock.release()
        #expect(!MirrorLock.isHeld(in: folder))
    }

    @Test("a sweep leaves a live mirror however old it looks, and removes it once it is let go")
    func liveMirrorSurvivesASweep() throws {
        // An audit left running overnight keeps its mirror's dates; only its lock says it's live.
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let live = try mirror(fixture)
        let liveContainer = live.root.deletingLastPathComponent()
        try backdate(liveContainer, days: 2)
        let abandoned = fixture.mirrors.appendingPathComponent("abandoned")
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)
        try backdate(abandoned, days: 2)

        let next = try mirror(fixture)
        defer { next.cleanup() }

        #expect(FileManager.default.fileExists(atPath: liveContainer.path))
        #expect(FileManager.default.fileExists(atPath: live.root.appendingPathComponent("Sources/A.swift").path))
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
        live.cleanup()
        #expect(!FileManager.default.fileExists(atPath: liveContainer.path))
    }

    // MARK: - The bound

    @Test("with nothing excluded, the bound counts what a link toward an included entry would copy")
    func boundCountsLinksTowardIncluded() throws {
        // No `excluded`: SwiftLint follows only the way to `included` entries, and so does the
        // count — it used to fire only with `excluded` set.
        let fixture = try makeFixture(config: "included:\n  - Sources/Kit\n", kitFiles: 3)
        defer { try? FileManager.default.removeItem(at: fixture.base) }

        #expect(throws: MirrorTooLargeError.self) {
            _ = try mirror(fixture, limit: 2)
        }
        #expect(fixture.containers.isEmpty)

        let shadow = try mirror(fixture, limit: 10)
        defer { shadow.cleanup() }
        #expect(FileManager.default.fileExists(atPath: shadow.root.appendingPathComponent("Sources/Kit/K2.swift").path))
    }

    // MARK: - Copies

    @Test("a readable file that can't be linked or copied fails the mirror, which leaves no container")
    func failedCopyFailsTheMirror() throws {
        // A mirror missing a file SwiftLint lints would count short.
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }

        #expect(throws: CocoaError.self) {
            _ = try mirror(fixture, failsCopies: true)
        }
        #expect(fixture.containers.isEmpty)
    }
}
