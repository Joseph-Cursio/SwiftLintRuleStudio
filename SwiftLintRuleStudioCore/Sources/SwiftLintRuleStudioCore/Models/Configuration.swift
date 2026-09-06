//
//  Configuration.swift
//  SwiftLintRuleStudio
//
//  Created by joe cursio on 12/24/25.
//

import Foundation

/// Represents a SwiftLint configuration
public struct SwiftLintConfiguration: Codable, Sendable {
    public var rules: [String: RuleConfiguration]
    public var included: [String]?
    public var excluded: [String]?
    public var reporter: String?
    public var disabledRules: [String]?
    public var optInRules: [String]?
    public var analyzerRules: [String]?
    public var onlyRules: [String]?

    nonisolated public init() {
        self.rules = [:]
        self.included = nil
        self.excluded = nil
        self.reporter = nil
        self.disabledRules = nil
        self.optInRules = nil
        self.analyzerRules = nil
        self.onlyRules = nil
    }
}

/// Configuration for a single rule
public struct RuleConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var severity: Severity?
    public var parameters: [String: AnyCodable]?

    nonisolated public init(enabled: Bool = true, severity: Severity? = nil, parameters: [String: AnyCodable]? = nil) {
        self.enabled = enabled
        self.severity = severity
        self.parameters = parameters
    }
}

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

// MARK: - File marker (satisfies file_name lint rule)

private enum Configuration {}
