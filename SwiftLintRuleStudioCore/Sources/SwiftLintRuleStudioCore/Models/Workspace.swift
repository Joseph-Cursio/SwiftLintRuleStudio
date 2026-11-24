//
//  Workspace.swift
//  SwiftLintRuleStudio
//

import Foundation

/// Represents a workspace/project
public struct Workspace: Identifiable, Equatable, Sendable {
    nonisolated public let id: UUID
    nonisolated public let path: URL
    nonisolated public let name: String
    nonisolated public var configPath: URL?
    /// When this workspace was last opened.
    ///
    /// It was called `lastAnalyzed` and no analysis ever wrote it. The only assignment in the
    /// package was in `WorkspaceManager.openWorkspace(at:)`, and only on the branch taken when the
    /// workspace is already in the recents list — so the value was `nil` until the *second* open
    /// and meant "opened at least twice", which is a property that fell out of two branches rather
    /// than one anybody chose.
    ///
    /// Naming it after what writes it is the smaller of the two available fixes. The other is to
    /// make the old name true by having an analysis write it, which is a feature rather than a
    /// correction, and nothing reads this field today either way.
    nonisolated public var lastOpened: Date?

    nonisolated public init(path: URL, id: UUID = UUID(), name: String? = nil) {
        self.id = id
        self.path = path
        self.name = name ?? path.lastPathComponent
        self.configPath = path.appendingPathComponent(".swiftlint.yml")
    }

    nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.path == rhs.path
    }
}
