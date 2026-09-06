import Foundation
@testable import SwiftLintRuleStudioCore
import SwiftLintRuleStudioCoreTestSupport
import Testing

/// `Workspace.lastOpened` records what actually writes it.
///
/// It was `lastAnalyzed`, and **no analysis ever wrote it**. The only assignment in the package was
/// in `WorkspaceManager.openWorkspace(at:)`, and only on the branch taken when the workspace is
/// already in the recents list — so the value stayed `nil` until the *second* open and meant
/// "opened at least twice", a property that fell out of two branches rather than one anybody chose.
///
/// The test that read the field asserted exactly that: `first == nil`, `second != nil`, under the
/// name "WorkspaceManager updates last analyzed time". It is gone, because it pinned the defect.
struct WorkspaceLastOpenedTests {

    private static let opened = Date(timeIntervalSince1970: 1_000_000)
    private static let reopened = Date(timeIntervalSince1970: 2_000_000)

    // MARK: - What writes it

    /// The half the old code missed. A workspace opened for the first time has been opened.
    @Test("the first open stamps it")
    @MainActor
    func firstOpenStampsIt() throws {
        let path = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(path) }
        let manager = WorkspaceManager.createForTesting(
            testName: #function, now: .fixed(Self.opened)
        )

        try manager.openWorkspace(at: path)

        #expect(manager.recentWorkspaces.first?.lastOpened == Self.opened)
    }

    /// The half it had. Re-opening moves the workspace to the top of the list and re-stamps it.
    @Test("re-opening re-stamps it")
    @MainActor
    func reopeningRestampsIt() throws {
        let path = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(path) }
        let manager = WorkspaceManager.createForTesting(
            testName: #function, now: .scripted([Self.opened, Self.reopened])
        )

        try manager.openWorkspace(at: path)
        try manager.openWorkspace(at: path)

        #expect(manager.recentWorkspaces.count == 1)
        #expect(manager.recentWorkspaces.first?.lastOpened == Self.reopened)
    }

    // MARK: - What was already stored

    /// A value saved under the old key is read as what it always was.
    ///
    /// Carrying it forward is not only politeness about someone's stored list: `lastAnalyzed` was
    /// written by `openWorkspace(at:)` and by nothing else, so a stored value *was* an open time.
    /// The rename is what makes it readable, not a change to what it holds.
    @Test("a value stored under the old key is read as lastOpened")
    @MainActor
    func legacyKeyIsReadAsLastOpened() throws {
        let path = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(path) }

        let defaults = IsolatedUserDefaults.create(for: #function)
        let legacy = [LegacyWorkspaceData(
            id: UUID(), path: path.path, name: path.lastPathComponent,
            configPath: nil, lastAnalyzed: Self.opened
        )]
        defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: WorkspaceManager(userDefaults: defaults).recentWorkspacesKey
        )

        let manager = WorkspaceManager(userDefaults: defaults)

        #expect(manager.recentWorkspaces.count == 1)
        #expect(manager.recentWorkspaces.first?.lastOpened == Self.opened)
    }

    /// The legacy key is read and never written, so a list that has been saved once stops carrying
    /// it. Without this, the fallback would quietly become permanent.
    @Test("saving writes the current key only")
    @MainActor
    func savingWritesTheCurrentKeyOnly() throws {
        let path = try WorkspaceTestHelpers.createMinimalSwiftWorkspace()
        defer { WorkspaceTestHelpers.cleanupWorkspace(path) }
        let manager = WorkspaceManager.createForTesting(
            testName: #function, now: .fixed(Self.opened)
        )
        try manager.openWorkspace(at: path)

        let stored = try #require(manager.userDefaults.data(forKey: manager.recentWorkspacesKey))
        let json = try #require(String(data: stored, encoding: .utf8))

        #expect(json.contains("lastOpened"))
        #expect(!json.contains("lastAnalyzed"))
    }
}

/// The shape as it was persisted before the rename, so the test writes real legacy data rather
/// than a hand-built string with a guessed date encoding.
private struct LegacyWorkspaceData: Codable {
    let id: UUID
    let path: String
    let name: String
    let configPath: String?
    let lastAnalyzed: Date?
}
